# osprey: Surface single-peak multiple-ID co-assignment in --model-diagnostics

## Branch Information
- **Branch**: `Skyline/work/20260808_peak_coassignment_diagnostics`
- **Base**: `master`
- **Created**: 2026-08-08
- **Status**: PR open, -Dataset All green, TeamCity 4128458 SUCCESS
- **GitHub Issue**: [#4522](https://github.com/ProteoWizard/pwiz/issues/4522)
- **Module**: `osprey`
- **PR**: [#4558](https://github.com/ProteoWizard/pwiz/pull/4558) (stacked on #4557); Rust: [maccoss/osprey#62](https://github.com/maccoss/osprey/pull/62) (stacked on #61)

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
      Brendan) - without it the 6.39x / 3.23x enrichments are not comparable to the target rate.
      `/code-review max` independently rediscovered this from the code alone, and added a
      point the earlier analysis missed: the twin pair is ALSO mislabelled as a PTM positional
      isomer, because `sameBase` compares stripped modified sequences and a decoy's library
      entry carries its target's sequence, so the two strip to the same string. The
      "of which PTM isomer" column therefore counts twins. Fix with the split, not separately.
- [ ] **Pass-2 experiment aggregate is the PASS-1 value on the DEFAULT path** - see the
      review section below. Prime suspect for open question 1.
- [ ] `_runBest` is O(files x distinct entry ids) and never released after `SealCutoffs` -
      projected several GB at 82 files. The panel is now always-on, and the 3-file gate
      cannot show this. Needs a real measurement before an Astral-scale run.
- [ ] Report the pass1 -> pass2 delta in the panel (how much co-assignment reconciliation adds)
- [x] Rebase onto #4553 once it is pushed, then re-run and re-measure pass 2
- [ ] Regenerate the diagnostics golden **on top of the #4553 branch** - it does NOT wait for
      #4557 to merge (Brendan, 2026-08-10). Their branch merges first, so the base already
      contains their fix and the golden captured here is the one master will have. Purely
      additive: the new `*.coAssign.*` metrics, and pass-1 decoy numbers 72 -> 468 / 96 -> 675.
      Anything ELSE moving is a finding, not a rebaseline.
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

**One more commit is expected on #4557** (and maccoss/osprey #61) addressing Copilot and
`/code-review` feedback, possibly as a force-push. Fetch and rebase onto their tip BEFORE the
expensive `-Dataset All` run and before blessing any golden - a baseline captured on a stale
base is silently wrong - and fetch once more immediately before opening the PR.

**Next session handoff**: read `ai/.tmp/handoff-20260808_peak_coassignment_diagnostics.md` -
it carries the night-session goal (stacked PR merge-ready by EU morning), the ordering with
#4557, the Rust PATH/VCPKG_ROOT trap, the regression gotchas, and the three open questions
that must NOT be silently resolved.

### 2026-08-10/11 (night session) - `-Dataset All` green, golden rebaselined, review applied

**`-Dataset All` on the integrated branch, before any change**: every leg PASS on all four
datasets except the six diagnostics-golden legs (mode1b + mode5), each exactly 28 issues, all
`metric not in golden`. **`mode1 (vs golden)` PASSES on all four**, so this branch moves no
search result. That was the precondition for rebaselining and it is now confirmed on four
datasets rather than one.

**Golden rebaselined** (`f91bd0d629`, committed separately from code as #4553 did):
`diagnostics.tsv` +28 / -0 on astral, stellar-libdecoy and stellar-gendecoy-entrap. Stellar
has no change because it is the one dataset that does not carry `--model-diagnostics`.
`protein_fdr.tsv` showed dirty in all four but with ZERO content change - pure line-ending
churn from the capture - and was restored rather than committed.

**`/code-review max` (`02711e0cde`)**. First invocation was mis-targeted at the BASE branch and
reviewed #4557 instead; that output is written up in `ai/.tmp/review-findings-for-4557.md` for
Brendan and the #4553 session, and nothing in their code was touched. Re-run against this
branch's range it returned 15 findings. Eight applied:

* **Resident pass-2 path lacked the decoy base-id m/z fallback** that `PeakCoAssignmentSource`
  has - and `BuildPrecursorMzLookup`'s own doc comment described the fallback it was not
  doing. The streaming comment records the cost of omitting it: ~97% of detected decoys
  dropped, decoy rate 30x too low. This one fed the PASS 2 panel, which has no
  admitted-vs-tallied check to expose it. The mandatory fix of the set.
* Gap-fill (`AssignPerRunQ`) and `RunSimpleFdr` never set `ExperimentAggregateScore`, so a real
  experiment q was persisted beside `ResetScores`' 0.0.
* A NaN apex RT casts to `int.MinValue` on net472 and threw out of a diagnostics-only panel.
* `PeakCoAssignmentSource.Build` promised "never throws" with no top-level guard.
* A missing `apex_rt` column substituted 0.0, which would report ~100% co-assignment from no
  data at all.
* The sidecar FORMAT VERSION was not in the first-pass resume validity key - live, since the
  format just moved 3 to 4.
* The HTML printed an enrichment ratio the KPI beside it withheld (gated on the row n only,
  not the target denominator).

**NOT fixed, deliberately - both are decisions, not oversights:**

1. **`ComputePass2TransferCompeteFull` recomputes experiment q but keeps the pass-1
   aggregate**, and this is the DEFAULT (`protein-compact`) path, not just `transfer-compete`
   as the reviewer framed it. The comparison stays self-consistent (both sides are pass-1
   scores) but the ACCEPTANCE SET is pass-2, so the boundary is "the lowest pass-1 aggregate
   among precursors pass 2 accepted". **This is the prime suspect for open question 1** (pass-2
   experiment decoys 71 against run 1,049). The obvious fix is wrong: `StreamedCompetitionState`
   exposes the winner only via `_winnerLoc`, keyed by BASE ID - which a target and its decoy
   SHARE - so deriving a pass-2 aggregate from it would hand every decoy its target's score.
   Needs a decision on what the pass-2 experiment aggregate should be.
2. **`_runBest` memory** - see the task list above.

Also refuted while verifying, so nobody re-derives it: the pass-2 panel does NOT mix rankings
via `AssignPerRunQ`. That path carries the experiment q from the pass-1 record too, so q and
aggregate are a consistent pass-1 pair. The mixing is real only on the default path in (1).

### 2026-08-10 - Earlier: pass 1 correct, sidecar v4 landed both sides

**Not committed at the time.** `C:\proj\pwiz` has 17 modified files, `C:\proj\osprey` 6. Held deliberately:
the ordering agreed with Brendan is that #4553 lands first and this branch rebases onto it,
because pass-2 numbers here are a symptom of that branch's zeroed-score defect and the two
branches need ONE joint golden rebaseline rather than two. See the "FOR THE #4553 SESSION"
section above for the two concrete asks (my new field needs adding to their seeding fix; their
sidecar decoder needs the v4 68-byte layout).

### 2026-08-10/11 (night session, later) - #4557 moved; rebased and re-captured

**Their branch moved mid-session, exactly as the handoff predicted.** `5679bc2c9d osprey:
Hardened the sidecar comparison after review` plus `d6d6a6d69b Merged master into ...`. That
voided the golden already captured, so the verification run was killed rather than spend an
hour validating a stale base.

Rebased both repos. Two conflicts, **both resolved in their favour**:

* `RestorePass1Scalars` - they restructured it to STAGE records and apply only when
  `ReadRecords` returns true, which is the fix for the partial-seeding finding written up for
  them in `ai/.tmp/review-findings-for-4557.md`. Kept their structure; moved the
  `ExperimentAggregateScore` seed into their apply loop.
* `FdrSidecars.ps1` - they replaced the parallel offset/name arrays with one
  `FdrSidecarField[] Fields` table, citing THIS branch's v4 layout by name as the drift risk
  it prevents, and added a pass-byte check plus checked size arithmetic. Kept all of it; added
  `experiment_aggregate_score` at offset 60 to their table.

We converged on the same defects from opposite sides, which is a good sign for the stack.

**Golden re-captured on the new base. `blib_summary.tsv` moved and was NOT blessed** - the
handoff says anything non-coAssign moving is a finding, so it was investigated rather than
committed: `8287.14162545012` -> `8287.141625450126`, a last-digit float-summation artifact
(~1e-12 relative) on a sum over 353,298 rows, and that gate compares at relative 1e-6. Their
own previous commit says "Reverted the blib_summary golden churn (that gate is relative 1e-6)",
so committing it would have re-introduced churn they had just removed. Reverted; the four
`protein_fdr.tsv` files were pure line-ending churn with zero content change and were likewise
reverted.

Final golden diff: `diagnostics.tsv` +28 / -0 on astral, stellar-libdecoy and
stellar-gendecoy-entrap. Nothing else.

**Rust PR opened**: maccoss/osprey#62, stacked on #61.

### 2026-08-10/11 (night session) - OPEN QUESTION 1 RESOLVED: it is compaction, not the boundary

Measured directly off the run's own sidecars, independent of the C# panel. Scripts committed:
`ai/scripts/Osprey/Entrapment/coassign_pass2_boundary.py` and `coassign_decoy_agg_compare.py`.

**The question**: pass-2 experiment decoys 71 against run decoys 1,049 is a ratio of 0.068,
where pass 1 gives 468/675 = 0.69. A 10x difference in that ratio between passes.

**Two hypotheses were killed by measurement, including the one this file called the prime
suspect an hour earlier:**

| hypothesis | prediction | measured |
|---|---|---|
| The pass-2 boundary is drawn from pass-1 aggregates against a pass-2 acceptance set, so it sits higher | pass-2 boundary > 0.0120 | **0.012008 at BOTH passes - identical** |
| Decoy aggregates are lost to `ResetScores` and read back as 0.0 | many 2nd-pass decoys at exactly 0.0 | **0 of 43,574** |

**The actual cause is compaction survivorship.** Distinct decoy precursors: **493,523 in the
1st-pass sidecars, 43,574 in the 2nd-pass** - an 11.3x cull. Of the 468 decoys that cleared the
bar at pass 1:

* **396 are absent from the 2nd-pass sidecar entirely**
* 0 are present with a reset aggregate
* 0 are present, non-zero, and below the bar
* **72 are still present and still clear it**

So the pass-2 experiment decoy row is not an artifact at all. It is the honest count of
"pre-compaction decoys that cleared the bar AND survived compaction". The bar itself does not
move between passes.

**The ratio in the question was never a meaningful quantity.** The experiment-scope count is
governed by compaction survivorship; the run-scope count is governed by a per-file boundary
recomputed over the compacted pool. Two different mechanisms, so their ratio compares nothing.
That is why run decoys can RISE (675 -> 1,049) while experiment decoys fall.

**Correction to this file and to PR #4558**: the deferred `ComputePass2TransferCompeteFull`
pairing issue (pass-2 q beside a pass-1 aggregate) is real as a description but is NOT the
cause here, and calling it the prime suspect was wrong. Measured, it moves the boundary by
0.000000 on this dataset. It should still be resolved on principle, but it is not urgent and it
does not taint the pass-2 numbers.

**One genuine discrepancy left, small but real**: the independent computation gets **72** decoys
clearing the pass-2 experiment bar; the panel reports **71**. Pass 1 agrees exactly (468 vs
468). One decoy differs at pass 2 - most likely a tie exactly at the boundary or a
classification edge. Worth a look before the decoy row is quoted.

#### The 72-vs-71 residual: two candidate mechanisms, neither confirmed

Not chased further tonight because a decisive test needs either the `entry_id` -> modified
sequence mapping (assigned by Osprey at library load, not present in the DIANN TSV) or new
panel instrumentation, and no more code could be pushed once TeamCity was running on the PR
commit. Both candidates are cheap to test in the morning:

1. **Precursor-key collision.** The panel keys precursors on `modseq|charge|decoy` taken from
   the LIBRARY entry, and the registry keeps the first arrival for a key. In this dataset
   decoys are reversals of BOTH targets and entrapment, so two distinct decoy entry_ids can
   carry the same library modified sequence and charge and collapse into one bucket. This is
   the same class of defect as RESOLVED item 3 above (which cost 396 of 468 decoys), just at a
   much smaller scale, so it deserves a look rather than a shrug.
2. **One decoy failing library m/z resolution** at pass 2 and being dropped by the panel's
   `double.IsNaN(mz)` guard. Less likely now that `BuildPrecursorMzLookup` has the base-id
   fallback, but not excluded.

**The cheapest discriminator is the one the pass-2 panel is missing**: pass 1 logs
"decoy precursors admitted N, tallied N" and that check is what makes its decoy row
self-verifying. Pass 2 has no equivalent - noted independently by `/code-review max`. Adding it
would have printed "admitted 72, tallied 71" and named the gap immediately. Add it first, then
the answer falls out of the next gate run instead of needing an offline script.

### 2026-08-10/11 (night session) - `_runBest` memory is now MEASURED, not projected

`ai/scripts/Osprey/Entrapment/coassign_runbest_size.py`, run on the gate's 3-file
StellarGenDecoyEntrap sidecars:

| | |
|---|---|
| distinct entry_ids per file | **979,128** (every sidecar row - entry_id is unique per file) |
| 3 files, live `_runBest` entries | 2,937,383 -> **106 MB** |
| **linear scale to 82 files** | 80.3M entries -> **2.84 GB** |

At 38 bytes per `Dictionary<uint,double>` entry (24-byte entry with padding, bucket array, and
growth slack) - conservative, and the raw count is printed so the assumption can be replaced.

**Context for judging it**: the gate's own resident-path report says Stage 6's survivor buffer
is already "~4.4 GB library + 0.197 GB/file live post-GC: ~20 GB at 82 files". So this is
roughly a **14% increase on an already-large footprint**, held from phase 1 through the entire
panel build, alongside both accumulators. Not obviously fatal, but it is a real cost that the
3-file gate cannot show, and **the panel is now always-on** because the opt-in tokens were
removed on a perf argument that only measured WALL TIME (0.4 s / 7.3M rows/s), never memory.
That argument should be re-read in light of this number.

**It is also mostly waste.** Only two populations are ever read back: per-file bests of
ACCEPTED target/entrapment precursors (for `SealCutoffs`) and aggregates of DECOY entries (for
`Includes`). Non-accepted target rows are inserted and never read. Accepted precursors run
~25-31k per file against 979k inserted, so filtering at insert - or dropping `_runBest` in
`SealCutoffs` the way `_runAccepted` / `_experimentAccepted` already are - should remove most
of it. Neither was attempted tonight: it changes panel-adjacent code after TeamCity had gone
green on the PR commit, and re-triggering needs Brendan's approval.

### 2026-08-10/11 (night session) - cross-impl parity RUN: C# and Rust agree on the v4 sidecar

The last unfinished task on this branch, and it turns a code-reading claim into a measurement.
`Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar -Files All`:

```
Stage 7 protein FDR (per-col 1e-9): PASS
Blib content (SQL row+col 1e-9):    PASS
FDR sidecars (per-field 1e-9):      PASS
   1st-pass: 1,448,698 record(s) compared
   2nd-pass:   994,899 record(s) compared
OVERALL: PASS -- Rust and C# end-to-end in-memory bit-parity at 1e-9 on Stellar 3-file
precursors: rust=29364  cs=29364  delta=0
```

**Non-vacuous, and specifically about v4.** The comparator REFUSES a sidecar whose version byte
differs from its `ExpectedVersion` rather than decoding at the wrong stride, and it is pinned at
version 4 / 68 bytes with the 8-field table. So decoding 2.44M records at all proves both
implementations wrote the v4 layout, and PASS proves `experiment_aggregate_score` agrees field
by field at 1e-9. Previously this branch could only claim the layouts matched from reading the
Rust source.

### ENVIRONMENT: running the Rust binary needs the vcpkg DLL dir on PATH, not just building it

Three attempts were spent on this, so it is written down. The Rust `osprey.exe` links native
OpenBLAS, so **running** it fails with exit `-1073741515` (`0xC0000135`, DLL_NOT_FOUND) unless
`C:\vcpkg\installed\x64-windows\bin` (which holds `openblas.dll`) is on `PATH`. `VCPKG_ROOT`
alone covers the BUILD and is what the docs describe; the run needs the bin directory too:

```powershell
$env:PATH = "C:\vcpkg\installed\x64-windows\bin;$env:USERPROFILE\.cargo\bin;$env:PATH"
$env:VCPKG_ROOT = 'C:\vcpkg'
```

The failure is opaque - a bare numeric exit code from a tool wrapper, naming no DLL - so it
reads like a crash in the run rather than a missing prerequisite. Worth adding to the
symptom -> missing-piece table in `ai/docs/osprey-development-guide.md` beside the existing
`VcpkgNotFound` build-time row.

Also note `Compare-EndToEnd-Crossimpl.ps1` defaults `-TestBaseDir` to `D:\test\osprey-runs`,
which on this machine holds no mzML; the regression data is under
`D:\Users\brendanx\Downloads\Perftests\osprey-testfiles-mzML-v2`. Pass `-TestBaseDir` explicitly.

### 2026-08-11 - ROOT CAUSE of the broken pass-2 decoy row, and the golden that pinned it

**I blessed a golden containing a catastrophically wrong pass-2 decoy count, and said it was
safe.** The additive check (+28 / -0) was done and passed; the VALUES were only sanity-checked
on stellar-gendecoy-entrap, the one dataset that happened to be correct. astral and
stellar-libdecoy were never looked at. Additive and garbage are not exclusive.

| dataset | pass2 exp decoys, blessed | after fix | pass2 exp targets |
|---|---|---|---|
| astral | **542,368** | **3,458** | 117,783 |
| stellar-libdecoy | **153,958** | **800** | 29,493 |
| stellar-gendecoy-entrap | 71 | 71 | 23,135 |

astral pinned 4.6x more decoys than targets, and 183x its own pass-1 count, from a rule meant
to admit about 1%. The gate then PASSED on it - a rebaseline turns a visible defect into a
certified one, and it would have gone red the day someone fixed it.

**Root cause**: `ComputePass2TransferCompeteFull` - the DEFAULT `protein-compact` path -
recomputes experiment q from a fresh competition but never wrote `ExperimentAggregateScore`.
Entries kept the pass-1 seed or `ResetScores`' 0.0, `SealCutoffs`' min-over-accepted collapsed
the experiment boundary to 0.0, and `Includes` admitted every decoy.

**Fix**: take the aggregate from the competition's own per-entry bests. The obstacle recorded
in the previous entry - "`_winnerLoc` is keyed by BASE ID, which a target and its decoy share,
so it would hand every decoy its target's score" - **was wrong**. `ComputeFullPopulationPrecursorFdrStreaming`
already keeps `bestTarget` and `bestDecoy` in SEPARATE maps, each tuple carrying its own
`entryId`. Building `aggByEntryId` from both is keyed by full entry_id and is the same
max-over-observations reduction `ComputeExperimentAggregateScoreMap` performs on pass 1.

`StreamedCompetitionState.ExperimentAggregateScore` returns **`double?`**, not a NaN sentinel
(Brendan's call, and the right one): null means "never entered the experiment fold", i.e.
off-stratum under protein-compact, and those keep their pass-1 aggregate because they keep
their pass-1 experiment q. NaN would have propagated silently into the v4 record, where the
sidecar comparators' `Math.Abs(a-b) <= tol` is FALSE for NaN vs NaN - a red gate on
byte-identical files. `double?` makes that caller fail to compile.

**Test gap closed, and verified by mutation.** The fixture never set the field, so every row
carried 0.0, the experiment boundary was 0.0, and every decoy was admitted regardless of what
the code did - which is why this shipped green. The decoy now has score 6.0 (clears the run
boundary of 3.0) and aggregate 1.0 (does not clear the experiment boundary of 2.0), so the two
scopes MUST disagree, and can only disagree if the experiment path reads the aggregate.
Reintroducing the defect gives 577 passed / 1 failed - confirmed, not assumed.

`-Dataset All` after the fix: **48 legs, 0 failures**.

### 2026-08-11 - Astral 3-file against the FULL target+decoy+entrapment library

The configuration `regression.ps1` skips to keep its wall clock down (its Astral leg carries no
entrapment). First run where BOTH known-false classes clear `MIN_N_FOR_ENRICHMENT`, so the
enrichment ratios render instead of being suppressed. 19m46s, 32 threads, 13 GB library.
HTML archived at `ai/.tmp/diagnostics-html/20260811-astral-full-entrapment/`.

| | pass1 run | pass2 run | pass1 exp | pass2 exp |
|---|---|---|---|---|
| target | 7.34% | 9.17% | 8.52% | 10.48% |
| entrapment | 15.66% (2.13x) | 16.43% (1.79x) | 26.91% (3.16x) | 32.29% (3.08x) |
| decoy | 29.53% (4.02x) | 20.72% (2.26x) | 43.29% (5.08x) | 31.11% (2.97x) |

Pass-2 decoys run 2,789 / experiment 2,716 = 0.97, against a target ratio of 0.91 - the fix
holds at full library scale with library-supplied decoys.

**A code comment is now contradicted and must be corrected.** `CoAssignmentData.PostReconciliation`
states as settled fact that reconciliation REMOVES co-assignment (2.17% -> 1.18%) while
enrichment RISES (3.14x -> 4.37x). On this dataset rates RISE (7.34% -> 9.17%) and enrichment
FALLS (4.02x -> 2.26x) - the opposite on both counts. The comment was written from Stellar and
reads as general. Fix by stating the direction is dataset-dependent, NOT by swapping one
dataset's claim for another's.

Also unexplained: target co-assignment is 9-10% here against the 4.3-5.1% the issue measured on
its 40-file Astral cohort. Different library and 3 files vs 40, but the gap should be understood
before any headline rate is quoted.

### 2026-08-11 - `_runBest` measured at REAL Astral scale, not extrapolated

| source | distinct entry_ids per file | projected at 82 files |
|---|---|---|
| Stellar, small library | 979,128 | 2.84 GB |
| **Astral, full entrapment library** | **4,184,823** | **12.14 GB** |

4.3x the earlier estimate, and the second row IS the SEA-AD configuration. `_runBest` is the one
structure that grows with FILE COUNT, so the 82-file run exercises it directly. Recorded before
that run finishes so the prediction is falsifiable.

perfviz on the 3-file run: managed peak 24.7 GB, total peak 37.3 GB, and the memory floor is
FALLING per file (-1.3 GB managed, -2.3 GB total) - so per-file work is bounded and `_runBest`
is the accumulating term, exactly as the review argued.

### 2026-08-11 - PR re-targeted to master; two more defects fixed; SEA-AD blocked on corrupt input

**PR [#4558](https://github.com/ProteoWizard/pwiz/pull/4558) is now based on `master`** (#4557
squash-merged as `4706ebdc8c`). Rebased with `--onto`, replaying only this branch's 8 commits;
the rebased tree was byte-identical to the pre-rebase tree, so the squash produced the same
content and the golden carried over unchanged. `Skyline/work/20260809_fdr_sidecar_parity` is
free to delete.

**Two defects found and fixed today, both mine, both caught by `/code-review max` on the
rebased branch:**

1. **The blessed golden pinned a broken pass-2 decoy row.** astral
   `pass2.coAssign.experiment.decoy.n` = 542,368 against 117,783 targets (183x its own pass-1
   count); stellar-libdecoy 153,958 against 29,493. Root cause:
   `ComputePass2TransferCompeteFull`, the DEFAULT protein-compact path, recomputed experiment q
   but never wrote `ExperimentAggregateScore`, so the boundary collapsed onto the `ResetScores`
   0.0 default and admitted every decoy. Fixed by taking the aggregate from the competition's
   own per-entry bests (`bestTarget`/`bestDecoy` are already separate maps, each tuple carrying
   its own entry id - the base-id objection recorded earlier was wrong). Now 3,458 and 800,
   both tracking the target run/experiment ratio.
   **How it was missed**: the +28/-0 additive check was done and passed; only
   stellar-gendecoy-entrap's VALUES were eyeballed, and that is the one dataset that was
   correct. Additive and wrong are not exclusive - check the values on every dataset.
2. **`_runBest` was O(files x distinct entry ids)** - `Dictionary<int, Dictionary<uint,double>>`,
   one map per file, live from phase 1 through the whole panel build, and `_runAccepted` the
   same. Measured 4.18M entries per file on the full entrapment library: 12 GB at 82 files,
   **~79 GB at 500** - past the whole budget of the 64 GB machine that target assumes. Run
   scope is a per-file question, so it now reduces at each `SealRunCutoff(fileIdx)` to the
   file's cutoff plus the admitted DECOY ids (O(decoys admitted), thousands not millions), and
   `ObserveCutoff` throws if a caller advances a file without sealing. `-Dataset All` after:
   48 legs, 0 failures, **golden byte-identical**.

`double?` over a NaN sentinel for `StreamedCompetitionState.ExperimentAggregateScore`
(Brendan's call): null means "never entered the experiment fold", and NaN would have
propagated into the v4 record where the sidecar comparators' `Math.Abs(a-b) <= tol` is FALSE
for NaN vs NaN - a red gate on byte-identical files.

**Test gap closed and verified by mutation**: the fixture never set the field, so every row
carried 0.0 and the experiment boundary was 0.0 regardless of the code. The decoy now has a
score that clears the run boundary and an aggregate that does not clear the experiment one, so
the scopes must disagree. Reintroducing the defect gives 577 passed / 1 failed.

**SEA-AD 82-file run is blocked on corrupt input, not on code.** 48 of the 82 mzML under
`D:\test\osprey-runs\sea-ad\mzml` are damaged: first 52 bytes overwritten with NTFS metadata,
and everything past some offset zeroed to the end (one file is ~13% data, another ~75%; all
lose the trailing index). **Sizes match the source EXACTLY**, so robocopy/xcopy/Explorer all
consider them current and copy nothing. The source on
`M:\home\brendanx\data\MacCoss\Osprey\SEA-AD\mzml` is intact (82/82 valid head AND tail), and
all 82 `.bin` spectra caches are intact on both sides. The damage is one contiguous block:
files SEA-AD-0015 through 0062 inclusive.

A 34-file run over the verified-good subset completed on the fixed build: 131.6 GB,
140,085,545 scored entries, 3h54m, memory floor FALLING (-102 MB/file managed, -269 MB/file
total), FirstPassFDR private peak 54.3 GB. Diagnostics HTML archived under
`ai/.tmp/diagnostics-html/`.

**Scripts added**: `ai/scripts/Repair-CopiedDataset.ps1` (content-based mismatch detection
and verified re-copy - size comparison finds nothing here),
`ai/scripts/Osprey/Archive-DiagnosticsHtml.ps1` (NOT `ai/scripts/`, as an earlier version of
this line and the 2026-08-11 handoff both claimed), and
`ai/scripts/Osprey/Entrapment/coassign_runbest_size.py`.

**Still open**: TeamCity 4128458 passed against `1a15f7ed` and is now STALE - four commits
newer, needs a re-trigger before merge (ask first). Copilot has never reviewed #4558; it did
not fire on the branch-based PR and may now that the base is master. Remaining `/code-review`
findings are listed above and in the review output.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260811_seaad_recopy_and_82file.md` before starting work.

### 2026-08-11/12 (night session) - the re-copy never ran; robocopy, not the drive

**`D:` is not failing, and the earlier evidence that it was is an artifact of the repair
script.** `Repair-CopiedDataset.ps1` detected the damaged files correctly by CONTENT and then
handed the copy to robocopy, which against the `M:` SMB source classified every one of them
`modified` - i.e. it had decided to copy - and then reported **Copied 0 / Skipped 1 / FAILED 0
in 0.04 s and exited 0**. Same with `/IS /IT`, same without them, same with default flags.
Zero bytes moved behind a success exit code, so the script re-verified the still-damaged file
and printed "still bad after copy" for all 48, which reads exactly like a dying disk.

Disproved directly: `Copy-Item` moves the same file at **108 MB/s** with a valid `<?xml` head
and `</indexedmzML>` tail, and a write-and-read-back test on `D:` passes. The script now copies
via `Copy-Item` (pwiz-ai `9614ed6`), and its "everything failed" summary no longer blames
hardware - **every file failing identically is the signature of a copy that never ran**, since
hardware that loses writes loses only some of them. That inference is now in the script.

**CORRECTION, same session, from `/code-review max`: the above diagnosis is WRONG about the
mechanism, and the Copy-Item swap was the wrong fix.** robocopy was behaving exactly as
documented.

A file rewritten IN PLACE keeps its length and its LastWriteTime but gets a **new NTFS CHANGE
time**. That is robocopy's `modified` class, and `modified` is a **SKIP** class - `robocopy /?`
says verbatim: *"otherwise the same. These files are not copied by default; specify /IM"*. So
`modified` in the listing never meant "it decided to copy"; it meant the opposite. Reproduced
on a file damaged that way on purpose:

| flags | Copied | exit | destination |
|---|---|---|---|
| `/J` (what the script used) | 0 | 0 | unchanged |
| `+/IS /IT` | 0 | 0 | unchanged |
| **`+/IM`** | **1** | **1** | **repaired** |

`/IS` is "Include Same" - the wrong class entirely, which is why adding it changed nothing. SMB
was incidental; the same happens on local NTFS.

**The swap also disarmed the script's own oracle.** `Copy-Item` is buffered, so the
verification immediately after it reads back the page cache the copy just filled -
"re-copied and verified: N" stopped being evidence that anything reached the platter. `/J` is
unbuffered and is the entire basis of that check. And "re-verify in a later session" does not
help: the Windows file cache is machine-wide and outlives the process, so a fresh pwsh still
reads the copy's own bytes. `ai/scripts/Osprey/SEA-AD/Clear-StandbyCache.ps1` already exists
for this and the script now points at it.

Fixed in pwiz-ai `4d4f46e`: robocopy restored with `/IM /IS /IT /J`, plus four defects the
review found in the same path - sampling never read the last `len/samples` bytes (73.7 MB of a
4.61 GB file, and the damage is trailing), `-Samples 0` silently disabled all comparison,
`-WhatIfOnly` created the destination directory, and every exit path returned 0 even with
files still broken.

**What the earlier claim got right**: `D:` is not failing. That conclusion stands on the
write-and-read-back test and on 82/82 verifying after the repair - it just was not robocopy
misbehaving.

### 2026-08-12 - ROOT CAUSE: a target inherits its paired DECOY's experiment q (base-id sharing)

**The experiment precursor q is keyed by BASE ID, which a target and its decoy share, so when
the decoy wins the competition the target inherits the winner's q.** Measured on the 82-file
SEA-AD 1st-pass sidecars, entirely independent of the C# panel
(`ai/.tmp/decoy_cutoff_check.py` plus the ad-hoc probes in that session):

| base | side | exp_agg | expPrecQ |
|---|---|---|---|
| 2363197 | target | -0.5623 | 0.009726 |
| 2363197 | **decoy** | **+0.7450** | **0.009726** |
| 2644981 | target | -0.0829 | 0.006404 |
| 2644981 | **decoy** | **+1.2159** | **0.006404** |
| 1205336 | target | -0.0521 | 0.004766 |
| 1205336 | **decoy** | **+1.5943** | **0.004766** |
| 3259837 | target | +0.1580 | 0.008911 |
| 3259837 | **decoy** | **+0.8606** | **0.008911** |
| 3266646 | target | +0.4942 | 0.009363 |
| 3266646 | **decoy** | **+0.7865** | **0.009363** |

Identical to 12 decimals in all five, and the decoy outscores the target every time. **The
codebase already states the principle this violates** - `ClampExperimentQToBestRun`'s doc
comment, describing the RUN-level floors: *"Both floors key on the target/decoy-specific
identity (never the shared base_id / bare sequence - a target must not inherit its paired
decoy's good run)."* The run floors were built to avoid exactly this; the experiment q
underneath them was not.

**Two consequences, different sizes.**

1. **Delivered results (small, but a real anti-conservative defect)**: 5 of 37,676 accepted
   precursors are reported at experiment q <= 1% having LOST their TDC pair. 0.013% of the
   accepted set, so no headline FDP moves - but they are false positives by construction.
2. **The panel's decoy row (large)**: those 5 carry aggregates from -0.5623 to +0.4942 while
   the true 1% threshold on the aggregate is **+0.70**. The decoy bar is
   `min(aggregate over accepted target/entrapment)`, so 5 records drag it 1.26 score units
   onto the DECOY's scale and admit **5,534 spurious decoys**.

**The decoy row has therefore been wrong on every dataset, and worse with more runs**, because
more runs give more chances to draw a contaminated pair into the accepted set:

| | accepted (targets+entrapment) | expected at 1% | reported | inflation |
|---|---|---|---|---|
| Stellar 3-file, pass 1 exp | 28,926 | 289 | 468 | 1.62x |
| SEA-AD 82-file, pass 1 exp | 37,676 | 377 | 5,911 | **15.69x** |

Draw the bar anywhere in the bulk instead and the definition is recovered exactly: p0.1 gives
391 (1.04x), p1.0 gives 381 (1.01x), against an expected 377.

**Why this was not caught before, and it is a methodological point worth keeping**: the
twelve-number oracle cross-check proved the C# panel reproduces the Python oracle - but the
oracle implements the SAME min-over-accepted rule, so it validated the IMPLEMENTATION and never
the DEFINITION. The independent check was arithmetic all along: at q <= FDR, decoys above the
bar must be `(targets + entrapment) * FDR`. The panel even logs its own accepted count beside
its tallied decoys, so on Stellar the expected 289 sat next to the reported 468 in the log. A
1.62x miss reads as rounding; it was the same defect at small scale.

**Hypotheses killed by measurement along the way** (recorded so nobody re-runs them):
* *The clamp lets low-score entries in.* No - `ClampExperimentQToBestRun` is
  `max(exp_q, run_floor)`; it only ever makes a q worse, so it cannot promote anything.
* *The clamp removes high scorers, stranding the bar.* No - 26,367 of the 26,734 rejected
  non-decoys above the old bar (98.6%) DO have a run passing `runBoth <= 1%`, so the clamp
  never touched them; they are simply below the true +0.70 threshold and correctly rejected.
* *The panel counts decoys that lost their pair.* No - 5,677 of the 5,911 admitted decoys BEAT
  their paired target and are legitimate TDC winners.

**Fix direction** (Brendan, 2026-08-12): fix the q assignment, not the panel's bar. Solving
the bar from the definition would produce a correct-looking decoy count while leaving the 5
contaminated targets in the accepted set. The q must key on the target/decoy-specific identity
the run floors already use.

**Golden impact - this CHANGES the branch's story.** Until now this branch claimed
`mode1 (vs golden)` PASSES on all four datasets, i.e. it moves no search result, and the
golden diff was purely additive (+28 diagnostics metrics / -0). Fixing the q assignment MOVES
THE DISCOVERY SET - contaminated pair-losers drop out of the reported set - so results goldens
will move on every dataset that has any. Brendan's call is that this favours fixing it here,
on a branch that already owes a golden rebaseline, rather than opening a second one.

### 2026-08-11/12 (night session) - the silent spectra-cache write (`126880972f`)

Added to this branch at Brendan's direction (it is not co-assignment work, but he chose to ship
it here rather than open a second PR - **say so in the PR description**, and note Copilot and
TeamCity have not seen it).

`SpectraCache.SaveSpectraCache` wrote multi-GB with nothing logged. On the 82-file SEA-AD
cohort that is **~4.1 GB and ~28 s per file**, and it surfaced only as an unexplained gap
between the reader's `100%` and `Loaded N MS1 and M MS/MS spectra` - measured 23 gaps >= 20 s,
mean 28.4 s, every one immediately before a `Loaded` line and nowhere else (~149 MB/s, i.e.
sustained sequential write). Long enough that a run looks hung.

Fixed by mirroring what `LibraryCache` already does for its own write: a `ProgressReporter` on
`IO_INTERVAL_SECONDS` over the MS2 record loop (its constructor also prints
`Writing spectra cache...`), plus a caller-side `Saved spectra cache (N MS2 + M MS1, X GB) to
'<path>'`. The path matters because `--work-dir` redirects it away from the data directory.

**Verification status, stated honestly**: 578 tests, zero warnings, and the mechanism is
byte-for-byte the pattern whose output is observable in this run's own log
(`Writing library cache...` / `Saved library cache (6324700 entries) to '...'`). The new line
has NOT been observed at runtime - the in-flight run uses a pre-change snapshot, and
`OspreyOutput.Out` is redirected under the test host so neither writer's line appears there.
Confirm on the next real run.

### 2026-08-11/12 (night session) - Copilot reviewed #4558; all four findings resolved

Copilot did fire once the base became master (open item 2 from the handoff). Commit
`ebcee57636`. The two interesting findings were settled by measurement rather than argument.

**`max()` over `ExperimentAggregateScore` is the wrong reducer, and the code comment defending
it had the distribution backwards.** The comment argued max() stops a `ResetScores` 0.0 stub
from pulling a real aggregate DOWN to zero. That only holds if aggregates are mostly positive.
Measured on this branch's own 34-file SEA-AD sidecars (`ai/.tmp/agg_zero_probe.py`):

| source | rows | exactly 0.0 | negative |
|---|---|---|---|
| 1st-pass sidecars (6 files) | 24,704,514 | **0** | 98.8% |
| 2nd-pass sidecars (6 files) | 4,481,762 | **2,511 (0.056%)** | 93.2% |

and the pass-2 experiment boundary is **negative in 6 of 6 files** (-2.33). So 0.0 is an extreme
UPPER outlier: under max() a stub wins every time it appears, which is the same
collapse-toward-zero that produced the 542,368-decoy golden.

**It is not a live defect today, and the reason is worth keeping**: all 2,511 stub rows carry
experiment q = 1.0, so none is accepted and none can set a boundary that is a min over ACCEPTED
precursors; and **none of them is a decoy**, so nothing is spuriously admitted. It is one
classification change away from mattering. Both reducers now prefer a real value over the
default. Pinned by `TestCoAssignmentAggregateStubDoesNotOutrankRealScore`, built so the two
rules give OPPOSITE answers - reverting to max() gives **577 passed / 1 failed**, confirmed by
mutation, not assumed.

Also fixed: `FdrScoresSidecar.ReadScalars` was the only reader not validating the pass byte
(every other one checks `header[9]`), and it floor-divided the record count so a truncated
sidecar read as merely short rather than corrupt. Both now rejected; its one caller passes
`Pass.FirstPass`. And a raw U+0001 byte embedded in the offender pair-key literal became a
named `PAIR_KEY_SEPARATOR` const - invisible in source and diffs, and any formatter that
normalized it would have merged unrelated pairs.

578 tests, zero warnings.

### 2026-08-12 - the SECOND decoy-row defect: pair-losers are counted

After `2704cc2dbf` the decoy row went 468 -> 338 against an expected 289 on
StellarGenDecoyEntrap - better, not right. Measured on the post-fix cross-impl Stellar C#
sidecars (boundary +0.250013, 31,164 accepted non-decoys, expected 312):

| decoys above the boundary | 415 |
|---|---|
| of which WON their target/decoy competition | **334** (expected 312, 1.07x) |
| of which LOST their pair | **81** |

**The panel admits every decoy whose aggregate clears the bar; TDC counts only competition
WINNERS.** A decoy that lost to its target is not in the ranking q was computed from, so
counting it inflates the row. Excluding the 81 leaves 334 against 312 - a 7% gap consistent
with conservative q being a step function.

So the decoy row had TWO stacked defects: the base_id q inheritance (dominant - 5,534 of the
5,911 on the 82-file run) and this one (the remainder). Fixing the first alone leaves ~1.17x.

**Hypothesis killed en route** (Brendan's, and worth recording because the arithmetic is the
lesson): that the clamp discarding target+entrapment entries with raw exp-q < 1% inflates the
ratio, since decoys cannot be clamped. The mechanism is real - 334 rejected non-decoys do sit
above the boundary - but its effect is **scaled by the FDR**: adding 334 to the denominator
adds 1% of 334 = 3 decoys, not 49. Explaining a 103-decoy excess that way would need ~10,300
clamped-out entries.

**Not yet fixed.** The rule the decoy row needs is: count decoys above the boundary that WON
their own target/decoy competition. Left for a session that can re-run the gate and rebaseline.

### 2026-08-12 - remaining logging gaps on the 82-file run (perfviz, 6 over 30 s)

```
 49s at 02:07:07 after: [WARN] CAL view: 47 of 82 file(s) have no captured calibration diagnostics
101s at 02:07:57 after: [MODEL-DIAGNOSTICS] peak co-assignment boundary (pass 1)   -> FIXED 7211398b74
195s at 06:25:09 after: Released library fragments for 0 of 6324700 entries        -> PARTLY fixed 891bd584f4
 56s at 06:46:59 after: 6110 protein groups pass 1.0% protein FDR
 38s at 06:47:55 after: (blank line)
 47s at 06:48:56 after: [ENTRAPMENT] Dropped 19279 unmatched entrapment peptides
```

**The 195 s is only PARTLY closed.** `891bd584f4` reports the survivor merge (89,068,375
observations into a HashSet). Two further steps sit in the same silence and are still
unreported: the per-file scalar sidecar path validation (82 files), and the protein-compact
stratum build (778,594 base_ids over 6,324,700 library entries). Both are in
`Pass2FdrSidecar.cs` between the "Released library fragments" line and the
`OSPREY_PASS2_QVALUE=protein-compact:` banner.

**Style debt introduced by that commit**: the merge loop body was NOT re-indented under its new
`using` block. Inspection passes and it compiles, but STYLEGUIDE says to take the bigger diff
and re-indent. Fix when next in the file.

The three gaps at 06:46-06:48 are Stage 7 / blib-write / entrapment matching and were not
investigated.

### 2026-08-12 - PASS 1 DECOY ROW NOW MATCHES ITS DEFINITION (288 vs 289)

Both defects fixed (`2704cc2dbf` q-inheritance, `37af75b993` winner-only). Measured on
StellarGenDecoyEntrap, pass 1, experiment scope, accepted = 28,694 targets + 228 entrapment:

| | decoys | vs expected 289 |
|---|---|---|
| original | 468 | 1.62x |
| after q-inheritance fix | 338 | 1.17x |
| **after winner-only rule** | **288** | **1.00x** |

**PASS 2 IS NOT SOLVED - 10 decoys against an expected 233.** The winner rule cut pass-2
experiment decoys from ~60 to 10, so that scope is now badly UNDER its definition. Consistent
with the documented finding that the pass-2 experiment population is governed by compaction
survivorship rather than by the boundary (396 of 468 pass-1 decoys are absent from the 2nd-pass
sidecar entirely), but it needs its own analysis before the pass-2 decoy row is quoted. The
enrichment is correctly suppressed (NaN) below MIN_N_FOR_ENRICHMENT, so the page does not
publish a ratio built on n=10.

Gate exits 1 as expected - goldens moved, self-consistency legs pass.

**Next, agreed with Brendan**: (1) 3-file Astral with the full target+decoy+entrapment library
(~20 min) - the only configuration where all three classes clear MIN_N_FOR_ENRICHMENT, so the
only one that exercises the decoy row against entrapment; (2) `--task FirstPassFDR` on a COPY
of the 82-file work dir (~63 min) to regenerate corrected 1st-pass sidecars and a corrected
pass-1 panel without redoing the 3h53m rescore; (3) full pass-2 diagnostics last.

#### Lead on the pass-2 under-count (10 vs 233), not yet tested

The winner-only rule cut pass-2 experiment decoys from ~60 to 10, i.e. **50 of the 60 were
pair-losers**. That is a much higher loser fraction than pass 1 (81 of 415, ~20%), and there is
a plausible mechanism: compaction keeps the SURVIVOR of each contest, so for a pair whose
target won, the target survives - and any decoy that also survives is disproportionately a
loser. If so, "count only winners" is correct in principle but is being applied to a pool whose
composition compaction has already skewed, and the honest pass-2 denominator is not
`(targets+entrapment) * FDR` at all.

Cheap test: on the 2nd-pass sidecars, count for each surviving decoy whether its paired target
also survived, and compare the loser fraction against pass 1. If losers dominate because
targets survive preferentially, the pass-2 decoy row needs a different definition rather than a
different threshold.
