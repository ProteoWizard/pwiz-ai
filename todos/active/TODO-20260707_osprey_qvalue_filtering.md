# TODO: Osprey q-value filtering — enforce run∧experiment on the emitted q

## Branch Information
- **Branch**: `Skyline/work/20260707_osprey_qvalue_filtering`
- **Base**: `master` (`31168db37b`)
- **Created**: 2026-07-07
- **Status**: Implemented + validated on Stellar; remaining = tests, golden re-baseline, self-review, TeamCity, Rust parity (see handoff)
- **Commits**: `ed0c5414bf` (clamp), `43d3a65da8` (Both-floor + merge-node re-clamp)
- **Worktree**: `C:\proj\pwiz`
- **Requested by**: Brendan (with Mike's blib observation)
- **Night handoff**: `ai/.tmp/handoff-20260707-osprey-qvalue-filtering.md`

## The problem
Osprey can report a peptide at experiment-level q < 1% that has **no run** passing run-level
q < 1%. Mike sees this in Skyline as blib ID lines that "shouldn't be possible" — the
compaction rule is *supposed* to guarantee every reported peptide clears run-level FDR in at
least one run. Same root issue makes the **Pass-1 experiment-wide** FDP calibration
anti-conservative (~2% at 1% q) while **Pass-2** (post-compaction) is ~0.9%: the calibration
"benefit" of Pass 2 is really just that the run-level gate got applied to the pool.

## Why it happens (verified in code)
The run-level requirement is enforced **once, indirectly, at the wrong place**:
1. **Compaction** (`FirstJoinTask.cs:605`) keeps a base_id iff `RunPeptideQvalue ≤ config.RunFdr`
   in ≥1 run — using **Pass-1** q-values, and only as a *pool* filter (a memory optimization).
2. **Pass-2 Percolator** (`Pass2FdrSidecar`, `--protein-fdr`) **recomputes** run-q and
   experiment-q from rescored features but **never re-applies** that gate. A peptide compacted
   in on its Pass-1 run-q can end up with every Pass-2 run-q > 1% yet still be reported.
3. The blib gates the reported set on **experiment-q only** (`MergeNodeTask.ComputePassingPeptides`),
   never re-checking run-q; the writer then gives the best (failing) run an ID line as a
   fallback (`BlibOutputWriter.cs:288-313`), which is what surfaces the violation.
4. **Level mismatch** (can fire even without `--protein-fdr`): compaction gates on run-**peptide**
   q, but "passed run-level" for the ID line uses `EffectiveRunQvalue(Both)` = max(precursor,
   peptide). A peptide can clear peptide-level run-q while no run clears Both.

Why experiment-q can beat every run-q at all: run-level and experiment-level are **independent**
target-decoy competitions; experiment-level dedups to each precursor's **best** observation (a
selection advantage), so it is optimistic by construction. The run gate corrects that bias.

## The fix (Brendan) — clamp each best-of aggregate to its constituents
Both experiment-level and peptide-level q are **best-of** reductions (experiment = each
precursor's best *run*; peptide = each peptide's best *charge*), each re-competed against a
*deduplicated / thinner* decoy null. A thinner null can hand the aggregate a q **below** its best
constituent's own q — that is the artifact. Neither monotonicity holds today. Enforce both:

> **experiment_q ← max( experiment_q , min-over-runs run_q )**
> **peptide_q ← max( peptide_q , min-over-charges precursor_q )**

i.e. a best-of aggregate can never be more confident than its best single member (valid because
Osprey aggregates by best-of, not by *combining* evidence). Together they make a consistent
hierarchy; gating output on the clamped q enforces "reported ⇒ a genuine constituent passed" at
any threshold, independent of whether/when Pass-2 Percolator recomputed q. Mike's missing-ID case
is the run→experiment clamp; "peptide more confident than any of its charges" is the symmetric
sibling. **Level match**: the min-over-runs should be over run-**Both** q, since the blib ID line
uses `EffectiveRunQvalue(Both)` — so "reported ⇒ some run passes at both granularities."

## Progress (2026-07-07 evening) — implemented + validated
Implemented as `ClampExperimentQToBestRun` in `PercolatorEngine` (Osprey.FDR), floored by best
run **Both** q (`EffectiveRunQvalue(Both)`) to match the blib ID line / `OspreyRunScores.RunQValue`.
Called in **two** places: (1) end of every `RunPercolatorFdr` pass (pass-1/2 `--model-diagnostics`
calibration); (2) `MergeNodeTask.Run` on the final post-Stage-6 pool before `WriteBlibOutput` —
authoritative, because Stage 6 zeroes moved-peak run-q *after* the pass-1 clamp.

Clean Stellar libdecoy runs (`--fdr-level precursor`), verified end-to-end:
- Pass-1 experiment-wide combined FDP @1%: **2.01% → 0.90%** (calibrated); Pass-2 unchanged 0.90%.
- blib ID-line violations (reported precursor with best-run-Both q > 1%): **3 → 0**; cost −3 disc.
- `--protein-fdr` Pass-2 unchanged at 1.48% (that's the depleted-null retrain = TRIC, out of scope).
- Osprey.Test 453 pass; build 0 warnings.

**Remaining (the night session):** unit tests for the clamp; **re-baseline the regression golden**
(output intentionally changed); full pre-commit gate; open PR + `/pw-self-review`; TeamCity green
(Stellar+Astral); a `maccoss/osprey` parity branch mirroring the clamp so
`Compare-EndToEnd-Crossimpl` passes. Full playbook + gotchas in the handoff above.

## Progress (2026-07-08 night session) — PR opened, re-baselined, self-reviewed, Rust mirrored
- **PR #4390** open (https://github.com/ProteoWizard/pwiz/pull/4390). Commits: clamp
  (ed0c5414bf) + merge re-clamp (43d3a65da8) + tests (0241abf7e9) + golden re-baseline
  (349a038d70) + self-review fix (f373038895).
- **Impact corrected (important):** on the real production path (standard Stellar/Astral,
  default --fdr-level Precursor, WITH --protein-fdr) the clamp drops ~4–5% of reported
  precursors (Stellar 59,768→56,534 −5.4%; Astral 167,285→160,358 −4.1%), = exactly the
  invariant violators (min-run-Both>1%), 0 residual. NOT the "−3" the evening (libdecoy,
  no-protein-fdr) run implied. Driver: --protein-fdr Pass-2 retrain anti-conservatism, which
  the clamp cleans up. Golden verified current (anchor run at base 31168db37b passed) — the
  diff IS the clamp. NEEDS Brendan's sign-off on the −5.4% tradeoff.
- **Golden re-baselined** (both datasets, 349a038d70); regression mode1/2/3 green Stellar
  post-fix. Astral via TeamCity 4082720 (pull/4390).
- **Self-review (fresh-context) round → f373038895:** fixed a real latent bug — peptide-q
  floor keyed by ModifiedSequence alone let a decoy lower its target's floor
  (anti-conservative); now keyed (ModifiedSequence, IsDecoy). No-op on default path (golden
  unchanged). Also TryGetValue + docstring. Added shared-modseq test. Design-question
  (run-Both floor under --fdr-level Precursor) documented, kept, flagged for Brendan.
- **Rust parity branch** `q-clamp-parity` @ ef27069 on maccoss/osprey (local, NOT pushed):
  faithful mirror incl. the peptide-key fix; fmt/clippy/tests green; 2 PARITY NOTE markers at
  HPC join-at-pass=2 sites (follow-up). Compare-EndToEnd-Crossimpl in flight.
- Morning report: ai/.tmp/morning-report-20260708-osprey-qvalue-filtering.md.
- **2026-07-08 AM (Brendan accepted the change):** --model-diagnostics re-check on libdecoy
  confirmed the clamp is a no-op on calibration (no-pfdr 0.90% intact; --protein-fdr 1.48%
  collapse persists = TRIC's job). Old-vs-new libdecoy drop is tiny (−262 / ~0.9% with
  --protein-fdr, −8 without) vs −5.4% on the gendecoy `stellar` regression — the −5.4% is a
  gendecoy-regime artifact ([[project_osprey_libdecoy_vs_gendecoy_calibration]]).
- **Copilot review addressed** (94f8e80bc3): treat null/empty ModifiedSequence as missing
  in the peptide floor (the (Modseq,IsDecoy) keying + doc were already in the self-review
  f373038895); 3 threads resolved. Golden + cross-impl parity re-verified unchanged.
- **Rust parity PR opened: maccoss/osprey#49** (branch q-clamp-parity @ 4c20174, base
  reconciliation-v3-first-pass-base-ids); cross-impl bit-parity Stellar+Astral PASS.

## Where to implement — options (decided: C, at two sites — see Progress)
- **(A) Just before blib** (`MergeNodeTask`/`BlibOutputWriter`): localized, but the plots,
  compaction, and any other consumer still see the raw q → duplication + drift.
- **(B) Just after the 2nd Percolator run** (`Pass2FdrSidecar`): fixes the reported set but not
  Pass-1 views, and only on the `--protein-fdr` path.
- **(C) Inside `PercolatorFdr` as part of calibration — emit q this way (RECOMMENDED).**
  After it computes per-run and experiment q, set the emitted experiment q to
  `max(experiment_q, min-over-runs run_q)` per base_id before returning. Then **every** consumer
  (Pass-1 plot, Pass-2 plot, blib gate, and even compaction if repointed) is automatically
  consistent — DRY, single source of truth, fixes all paths at once. It has all the per-run q's
  in hand already (it computes them), so the min-over-runs is free.

## Open design questions
- **Levels.** min-over-runs at which scope — run-Both (to match the ID-line semantics) or
  per-level (adjust exp-precursor by min-run-precursor, exp-peptide by min-run-peptide)? Match
  whatever `EffectiveRunQvalue`/the ID line use so the invariant is exact.
- **Compaction.** Keep it as a pool/memory optimization on raw run-q (still valid), or repoint
  it to the effective q? At minimum the *reported* gate must use effective q; compaction can stay
  looser without reintroducing the artifact.
- **Gap-fill / zeroed reconciled rows.** Confirm appended gap-fill and Stage-6-zeroed
  observations get a sane run-q so min-over-runs isn't accidentally 1.0 for a real precursor.
- **Cross-impl parity.** This intentionally changes emitted q vs Rust (Rust doesn't do this). It
  will move the committed golden and break the C#/Rust equality signal — a *wanted* divergence
  (Mike flagged it). Coordinate: re-baseline `regression.ps1` golden, decide whether Rust mirrors
  (see [[project_osprey_parity_removal_sprint]]).

## Validation
- **Primary: `--model-diagnostics`** (the interactive HTML — Summary / Competition / Density /
  FDR-calibration tabs; FDP computed in-process). After the fix, the **Pass-1 experiment-wide**
  FDR-calibration curve should drop from ~2% to ~0.9%, matching Pass 2 — the direct proof the
  run-gate is now on the emitted q. Keep exercising / improving `--model-diagnostics` as the
  primary FDR-assessment surface; FDRBench (`--fdrbench-pass both`,
  [[TODO-20260707_osprey_fdrbench_pass_both]]) now serves to validate the *plot math*, not as the
  primary readout.
- **Invariant test**: assert no reported (blib) peptide has *every* run's `EffectiveRunQvalue(Both)`
  > `config.RunFdr` (Mike's finding as a regression guard); analogously no peptide passing with
  every charge's precursor-q above threshold.
- Standing gates: `regression.ps1` (expect a golden re-baseline), `Build-Osprey.ps1 -RunInspection -RunTests`.

## Related
- [[project_osprey_pass2_gate_divergence]], [[project_osprey_pass2_recalibration_inflates_fdr]]
  (the same Pass-2-recompute-without-re-gate family; TRIC is the sibling fix for *scores*, this
  is the fix for the *gate*).
- [[TODO-osprey_assumption_failure_detection]] (the run-count / reproducibility filter Brendan
  raised is a complementary, separate lever).
