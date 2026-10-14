# TODO-20260710_osprey_pass2_recalibration_fix.md -- Stop recalibrating q in the 2nd Percolator pass; add a kill-switch now and a TRIC-transfer alternative

## Branch Information
- **Branch**: `Skyline/work/20260710_osprey_pass2_recalibration_fix`
- **Base**: `master`
- **Created**: 2026-07-10
- **Status**: Completed
- **PR**: [#4410](https://github.com/ProteoWizard/pwiz/pull/4410) (merged 2026-07-11 as 2985b4d063)

### 2026-07-11 - Merged
PR #4410 merged to master as squash commit **2985b4d063**
("Added OSPREY_PASS2_QVALUE transfer mode as a 2nd-pass Percolator-retrain off-switch").
Shipped Part A: the `OSPREY_PASS2_QVALUE` selector (`percolator` default byte-identical to the
committed golden; `transfer` = frozen 1st-pass model + full pre-compaction score->q table),
consolidating the three `d52cf7db17` prototype env vars, plus `TestTransferScoreQTable`. Both AI
review gates cleared (self-review CRITICAL resident-pool gate + a follow-up feature-load bug the
plain-transfer verification exposed; Copilot's 4 comments, threads resolved). Gates green:
Debug + 505 tests + 0-warning inspection; `regression.ps1 -Dataset Stellar` mode1/2/3 byte-identical;
**Osprey Perf/Regression build #150 SUCCESS on fc95bb335e (Stellar + Astral)**.
A/B validated the effect on SEA-AD 20-file r=0.5 (deterministic): Pass-2 exp-wide true FDP@1%q
3.61% (percolator) -> 1.11% (transfer), Pass-1 identical 0.835%.
**Deferred (Part B, not in this PR):** the surgical Design 1 (transfer only the changed minority to
recover IDs the coarse whole-pool transfer loses on r=0.5), Design 2 (pre-Percolator gap-fill), the
`tric`/`retrain_fullnull` mode, cross-mode-resume sidecar mode-tagging, the `PercolatorResults`
memory pin, and the companion doc for Mike. Follow-up backlog TODOs filed: FDR entrapment-collapse
investigation, model-diagnostics Pass-1/2 switch, calibrator-selection review.

## Progress (2026-07-11, night session)
Part A IMPLEMENTED (percolator default + transfer). Consolidated the three
`d52cf7db17` prototype env vars into a single `OSPREY_PASS2_QVALUE` selector; the
`retrain_fullnull`/variant-vii probe is deferred to Part B per this TODO. Re-derived
against current master (two `RunPercolatorFdr` overloads, projection+resident+
model-diagnostics pass-2 paths) rather than cherry-picking the stale prototype diff.

Files changed:
- `Osprey.Core/OspreyEnvironment.cs`: `OSPREY_PASS2_QVALUE` (`percolator` default /
  `transfer`), `Pass2TransferQ`, `Pass2QValueUnrecognized`, normalized once at startup.
- `Osprey.Tasks/PipelineByproducts.cs`: `FirstPassPercolatorModel`, `FirstPassScoreQTable`.
- `Osprey.FDR/PercolatorEngine.cs`: optional `captureModel` hook on the FdrEntry
  `RunPercolatorFdr` overload (no-op on the default path).
- `Osprey.Tasks/FirstJoinTask.cs`: transfer added to `needsResidentFirstPassPool` (so the
  1st pass runs resident and captures the frozen model + builds the full-population table);
  first-pass wrapper publishes `FirstPassPercolatorModel`; builds+publishes
  `FirstPassScoreQTable` after `LogFirstPassResultsAndDump`.
- `Osprey.Tasks/Pass2FdrSidecar.cs`: mode log + unrecognized warning; transfer routed to
  the resident path; `ComputePass2Resident` switch calls `TransferQFromFrozenModel` instead
  of the retrain when transfer + byproducts present (bool return -> falls back to retrain
  otherwise); helpers `BuildFullPopulationScoreQTable`, `ScoreWithFrozenModel`,
  `AverageFoldModel`, `TransferQWithTable`, `BuildScoreToQTable`, `LookupQForScore`.

Stale-doc-ref fixes (Part A item): the `(--protein-fdr)`-gated wording the TODO flagged in
`model-diagnostics-template.html`, `ModelDiagnosticsReport.cs`, `ModelDiagnosticsData.cs`
was ALREADY corrected by #4408 (now in master) -- current wording is "any reconciled run",
accurate for the post-#4395 always-on 2nd pass. No further action; the transfer-mode
"null pass-2 model view" case is also covered by the existing "not retrained on this run" copy.

Gates:
- Build Debug + 505 tests (502 pass/3 skip, incl. TestTransferScoreQTable) + `-RunInspection`
  0 warnings/0 errors: GREEN (the 9 SystemMemory.cs warnings are the #4379 local flake, untouched file).
- `regression.ps1 -Dataset Stellar` mode1/2/3 (default percolator byte-identity): PASS on commit
  01e0e4dca7 (blib 50,237,440 identical across straight/HPC/resume + vs golden). Re-run after the
  self-review fix commit pending the Release exe freeing (A/B percolator arm holds it).

Self-review (fresh-context agent, PR #4410) - all findings addressed in commit fd2c15efaa:
- CRITICAL: `PerFileScoringTask.needsResidentPool` did not mirror the `FirstJoinTask` gate for
  `Pass2TransferQ` -> a plain `transfer` run (no --model-diagnostics, default projection) split
  to empty stubs and ran the 1st pass on zero entries. The A/B harness masked it (--model-diagnostics
  forces resident in both gates). FIXED: added `|| Pass2TransferQ` to PerFileScoringTask.
- MEDIUM: cross-mode resume in one --output-dir reuses the other mode's 2nd-pass sidecar q (sidecar
  not mode-tagged) -> documented "fresh output dir per mode" limitation; mode-tagging deferred to Part B.
- MEDIUM: transfer flattens precursor/peptide + run/experiment q to one value -> commented; Design 1
  (Part B) preserves per-level survivor q.
- LOW: guarded the add-only frozen-model Publish; noted the PercolatorResults memory pin (Part B).
- Verified clean: default byte-identity, ScoreWithFrozenModel parity w/ ScorePopulationAndComputeFdr,
  table monotonicity + clamps, table-build timing, HPC/resume safe-degrade-to-retrain.
- Follow-up (agent): confirm a plain `transfer` run (no --model-diagnostics) logs the "confidence
  transfer" line, not the fallback warning. RAN on Stellar (no --model-diagnostics) -> it EXPOSED
  a SECOND-layer bug: the resident 1st pass STREAMS PIN features into the SVM (lean stubs) and
  never persists them to FdrEntry.Features, so BuildFullPopulationScoreQTable found 0 entries and
  transfer SILENTLY FELL BACK to the retrain. --model-diagnostics does not populate Features either,
  so the A/B transfer arm would have fallen back too (looked identical to percolator). FIXED in
  fc95bb335e: BuildFullPopulationScoreQTable now streams features from the Stage-4 parquet by
  ParquetIndex (like the score pass). Re-verified on Stellar: "built FULL-population score->q table
  from 1000 entries (0 skipped ...q range [5.0E-4, 0.974])" + "re-scored 392713 entries with the
  FROZEN 1st-pass model", NO fallback, exit=0. See [[reference_osprey_resident_firstpass_streams_features]].

Commits: 01e0e4dca7 (Part A) -> fd2c15efaa (self-review CRITICAL gate) -> 0d3645ead1 (Copilot) ->
fc95bb335e (transfer feature-load fix). Head fc95bb335e.
TeamCity on pull/4410 (final head fc95bb335e): 4089588 Perf/Regression, 4089589 unit.

## A/B RESULT (percolator vs transfer, --model-diagnostics, SEA-AD 20-file r=0.5b)
Both arms same branch build, stage1-4 hard-linked, differ ONLY in OSPREY_PASS2_QVALUE.
Deliverable: D:\test\Pilot-MTG-Tissue-May2026\runs\pass2-ab-percolator-vs-transfer.html
(+ per-arm seaad.model-diagnostics.html in runs\seaad-20files-entrapment-r0.5-{percolator,transfer}).

True combined FDP @ 1% reported q (from --model-diagnostics entrapment calibration):
| view              | percolator     | transfer       |
| Pass 1 exp-wide   | 0.835% / 36212 | 0.835% / 36212 |  (identical - the calibrated reference)
| Pass 2 exp-wide   | 3.612% / 64995 | 1.108% / 31586 |  <- transfer restores toward Pass-1 calibration
| Pass 2 per-run    | 3.634%         | 1.108%         |

=> On CURRENT post-#4395 master, the always-on 2nd-pass Percolator retrain is anti-conservative
on SEA-AD r=0.5 (3.61% true FDP at 1% reported q, accepting 64,995 targets); transfer cuts that
to 1.11% (31,586 targets), close to the Pass-1 0.835% calibration. Directly demonstrates the
TODO thesis on the real current code.

DETERMINISM (verified): percolator-rep2 reproduced 3.612%/64995 EXACTLY; the two runs'
.1st-pass.fdr_scores.bin are byte-identical -> my exe is deterministic, the A/B gap is purely
the q mode (not run noise). The reconciled parquet differs byte-wise across runs (minor Stage-6
gap-fill ordering; does not move the reported FDP). The earlier "baseline" 0.844% was a PRE-#4395
build (existing run seaad-20files-entrapment-r0.5, exe e300d3fd02 off #4399) -> not comparable;
#4395 is what introduced the always-on retrain this fast-follow addresses.
NOTE: transfer here is the coarse whole-pool transfer; on r=0.5 it is CONSERVATIVE (31,586 <
Pass-1 36,212) because the full-pop table's min q is ~0.0095 (this data's FDR floor). Part B's
surgical Design 1 (keep unchanged survivors' Pass-1 q; transfer only gap-filled/moved peaks)
should recover the IDs while keeping calibration - the next validation target.

## Status
**Active (created 2026-07-09; started 2026-07-10).** Promoted from the forward-reference left by
`completed/TODO-20260701_osprey_separate_protein_reporting_from_rescue.md` (see its
2026-07-02 oracle overturn and 2026-07-04 disposition) and
[[project_osprey_pass2_recalibration_inflates_fdr]]. Trigger to raise priority now:
pwiz **#4395** ("Fixed Osprey-Rust Percolator parity divergences") makes the 2nd-pass
Percolator retrain **run by default and removes the only way to avoid it** -- so the
anti-conservative q-values are now what a plain `osprey ... ` run ships, with no
committed off-switch. Before #4395 the implicit escape hatch was "omit
`--protein-fdr`"; #4395 decouples the 2nd pass from that flag (Rust parity), closing
the hatch.

**#4395 disposition (2026-07-09): ACCEPT.** With the C#/Rust parity gate now standing
in `/osprey-development`, matching Rust (always-on 2nd pass) is the correct short-term
move; the always-on behavior is not a #4395 defect but the pre-existing Rust design it
faithfully ports. This TODO is the **fast-follow** that (A) re-adds an off-switch and
(B) opens the campaign to replace the reduced-pool retrain. Do NOT block #4395 on this.

Reported by Brendan (has already told Mike a second Percolator pass is not a valid
way to estimate q). Goal: **go to Mike with a proposed solution + a written case**,
not just a complaint.

## The problem: pass 2 re-estimates q on a decoy-DEPLETED null
Osprey's 2nd pass does two separable things to the post-reconciliation reported pool:
1. **re-picks / re-scores** peaks against the consensus (this HELPS -- ~+390 real IDs
   at true 1% FDP); and
2. **re-estimates q** by retraining Percolator and recomputing a target/decoy null
   **on the reported pool** -- but first-pass compaction has already stripped most
   decoys from that pool, so the null is decoy-depleted and target-selected. Retraining
   on it makes the model over-confident and the q-values **anti-conservative**.

Step 2 is the entire anti-conservative source; step 1 is fine. This is visible in the
`--model-diagnostics` HTML: the **2nd-pass composite-score distribution** shows the
target histogram stepping/jumping away from the (too-narrow) decoy-normal fit, and the
**Pass 2 FDR-calibration** curve sits well above y=x.

### Measured, one hash-stamped binary each time
Oracle A/B/C (Stellar libdecoy, precursor, `--fragment-tolerance 0.4`; from the
2026-07-02 finding, `ai/.tmp/pr2-oracle-finding.md`):
- A: `--protein-fdr` OFF -> 27050 disc, FDP **0.92%** (good)
- B: `--protein-fdr` ON -> 30788 disc, FDP **1.57%** (bad)
- C: `--protein-fdr` ON + `OSPREY_PASS2_NO_RECALIBRATE` -> 27050 disc, **0.92% == A exactly**
- E (best validated): carry the FULL 1st-pass score->q null to Stage 7 + transfer -> **0.86%**

Reproduced fresh on the **#4395** binary, 2026-07-09 (Stellar libdecoy, precursor,
`--model-diagnostics`, **no `--protein-fdr`**), from the same report's two passes
(`D:\test\osprey-runs\_mdiag\stellar\stellar.model-diagnostics.html`):
- **Pass 1** (what the old no-`--protein-fdr` default shipped): 26,775 disc @1% q,
  combined true FDP **0.90%** -- calibrated.
- **Pass 2** (what #4395 makes the default): 30,242 disc @1% q, combined true FDP
  **1.47%** -- anti-conservative. HTML curve MATCHES stock FDRBench (r=0.98), so the
  diagnostics are faithful; the inflation is real, not a plotting artifact.

So #4395 trades ~+3,500 IDs (+13%) for ~1.6x the true error rate, by default, with no
opt-out.

## Part A -- SHORT TERM: commit a pass-2 q kill-switch (fast-follow PR after #4395)
Restore the ability to get accurate q while the real fix is designed. Add ONE env var
in `Osprey.Core/OspreyEnvironment.cs` (same pattern as `LoessClassicalRobust` /
`UseFdrProjection`), read once and cached, consulted at the pass-2 site
(`MergeNodeTask` -> `Pass2FdrSidecar.ComputeAndPersist`).

Proposed: **`OSPREY_PASS2_QVALUE`** with modes (keep the peak re-scoring in all cases;
only the q step changes):
- `percolator` (default): current behavior -- retrain Percolator + recompute the null
  on the reported pool. Preserves Rust parity as the default.
- `transfer` (a.k.a. off/no-recalibrate): do NOT retrain or re-estimate a null; score
  the reconciled peak with the **frozen 1st-pass model** and map through the 1st-pass
  **score->q table** (co-monotonic). This is oracle cells C/E and the direction of the
  real fix. Equivalent to the prototype `OSPREY_PASS2_NO_RECALIBRATE`.

Wiring already prototyped (uncommitted) on branch
`Skyline/work/20260704_osprey_pass2_recalibration` (commit **d52cf7db17**):
`OspreyEnvironment.cs` + `Pass2FdrSidecar.cs`, env vars `OSPREY_PASS2_NO_RECALIBRATE`
/ `_TRANSFER_Q` / `_RETRAIN_FULLNULL`. Consolidate those three prototypes into the
single `OSPREY_PASS2_QVALUE` selector for the commit.

Also fix the now-stale references #4395 leaves behind (they assert the 2nd pass is
`--protein-fdr`-gated, which is no longer true) so the diagnostics don't mislabel a
no-`--protein-fdr` run -- into #4395 itself if still open, else this fast-follow:
- `Osprey.Tasks/ModelDiagnostics/model-diagnostics-template.html:326`
  (`desc:"post-reconciliation retrain on the reported pool (--protein-fdr)"`)
- `Osprey.Tasks/ModelDiagnostics/ModelDiagnosticsReport.cs:166-167`
- `Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs:418-421` (`BuildModelPass2` doc)

## Part B -- THE REAL FIX: don't retrain on a reduced pool; two candidate designs
Anchoring insight (Brendan, from the #4395 HTML, 2026-07-09): the **Pass-1
experiment-wide** calibration is accurate -- the combined-FDP curve tracks y=x (mildly
conservative) from 0 to 100%, 0.90% at 1% q. So the 1st-pass model already gives a
well-calibrated, monotone score->q map over the FULL score range. The second pass throws
that away by retraining Percolator and re-estimating a null on the compacted (q<=0.01)
pool, which is decoy-depleted and target-selected -> the flat ~1.47% curve. The fix is
to **stop remodeling everything kept from the 0.01 cutoff** and instead assign q only to
what genuinely changed, or avoid the reduced-pool retrain structurally. Two designs to
A/B and take to Mike:

### Design 1 (post-Percolator, minimal / low-risk): transfer q to the changed minority only
Almost nothing in the reported pool needs a new q. Partition what Stage 6 produces:
1. **Unchanged Pass-1 survivors** (the large majority, q<=0.01, peak not moved) -- KEEP
   their existing Pass-1 experiment-wide q verbatim. No re-score, no re-estimation; the
   calibrated majority is preserved bit-for-bit.
2. **Gap-filled peaks** (precursor absent in this file, passing in a sibling, scored at
   consensus RT) -- genuinely new detections: score with the **frozen 1st-pass model**
   and read q from the **1st-pass score->q table**.
3. **Reconciliation-moved peaks** (multi-charge consensus / RT reconciliation re-points
   a peak; Stage 6 zeroes their run-q; a move can only LOWER the score to agree with
   consensus) -- same transfer; because the score only drops, the transferred q can only
   worsen (conservative, correct direction).
This is oracle variant (iii)/cell E made explicit about WHICH peaks get the transfer.
Requirement: the transfer table must be the **full** 1st-pass score->q envelope (incl.
the high-q/failing region compaction discards), not one rebuilt from passing-only
survivors (all-low-q, does not calibrate) -- that full envelope is exactly the Pass-1
experiment-wide curve above. The pass-2 SCORE gain (~+390 real IDs at true 1% FDP) comes
from the better peak choices, NOT from re-estimating q, so this keeps the IDs and
restores calibration (cell E = 0.86%).

### Design 2 (pre-Percolator, structural): gap-fill BEFORE the single Percolator training
Move gap-fill candidate generation ahead of Percolator so gap-filled precursors are
scored and separated in the SAME single training as everything else -- one model, one
null, no second training, and no using Percolator's own initial separation / q to select
the pool it then retrains on (the circularity that biases the reduced pool). Eliminates
the reduced-pool retrain entirely rather than correcting it after the fact.
Open design question to resolve: gap-fill today needs cross-replicate **consensus RTs**,
which come from first-pass IDs -- so either (a) keep a cheap first separation only to
derive consensus RT + gap-fill targets, then fold those candidates into the one
Percolator training set (still a single training/null); or (b) score library precursors
more liberally across files up front so there is no detect-then-gap-fill split at all.
More invasive than Design 1; likely the better long-term answer. Capture feasibility
during the sprint.

### Deliverables (both designs behind the one selector)
1. `OSPREY_PASS2_QVALUE` gains the Design-1 `transfer` mode (consolidating the
   `d52cf7db17` prototypes); Design 2 explored and, if feasible, added as a mode /
   pipeline-order option. All A/B-able against `percolator`.
2. **Oracle A/B, one FDP curve per mode**, via the existing harness --
   `ai/scripts/Osprey/ModelDiagnostics/Run-ModelDiagnostics.sh stellar [pfdr]` +
   `Compare/Compare-Fdrbench-Html.py --pass 2` (already renders both passes + cross-checks
   stock FDRBench). Target: the alternative returns Stellar to ~0.90% combined FDP while
   keeping the pass-2 re-scoring ID gain.
3. Secondary A/B (variant vii, optional): keep the retrained SCORE for extra ranking
   power but calibrate it against a FULL non-depleted null, vs the frozen-model score of
   Design 1. Lead with the simpler frozen-model transfer; treat vii as an upside probe.
4. Decide the **default** (percolator vs the alternative) WITH Mike; keep all modes
   behind the selector until then. Do NOT flip the default unilaterally (see
   [[feedback_bit_parity_tolerance]] / [[feedback_hard_fail_over_warn_proceed]]: an
   anti-conservative default a user trusts is exactly the "silently-invalid output" case).
5. **Rust parity**: changing the default away from 2nd-pass Percolator is a deliberate
   divergence from Rust and must be a dual C#+Rust change with Mike's sign-off (mirror the
   rescue-removal lesson in the 20260701 TODO). Until then C# default stays `percolator`
   to hold the standing `/osprey-development` parity gate.

## Companion document (the case for Mike) -- SEQUENCED LAST, after the sprint
Deferred deliverable, written only once the sprint has produced the validated method +
A/B numbers. It goes in **pwiz** (`pwiz_tools/Osprey/docs/`, sibling of
`fractional-entrapment.md`) -- a more official location -- so do NOT create it up front;
land the code + oracle results first, then write the doc from real numbers. Name TBD
(e.g. `pass2-confidence-transfer.md`). Intended argument, so Brendan brings a proposed
solution rather than an objection:
- **Why a 2nd Percolator pass on the reduced pool is invalid**: retraining re-estimates
  a target/decoy null on the post-compaction pool, which is decoy-depleted and
  target-selected; the null no longer reflects the incorrect-match distribution, so q is
  anti-conservative. Show the mechanism + decoy-depletion count.
- **The evidence**: the oracle A/B/C/E table and the #4395 Pass-1-vs-Pass-2 numbers
  above; figures = the accurate Pass-1 experiment-wide curve ("the asset we protect")
  next to the broken Pass-2 composite-score cliff + flat Pass-2 calibration curve
  (screenshots at `ai/.tmp/screenshots/sessions/Screenshot 2026-07-09 14{2932,2448,2512}.png`).
- **The alternative(s)**: Design 1 (transfer q to the changed minority; cite Roest 2016
  TRIC) and, if it pans out, Design 2 (gap-fill before a single Percolator training).
- **The recommendation**: from the winning A/B; keep `percolator` available via the env
  var for parity/comparison.

## Gates (judge on the entrapment oracle, within ONE hash-stamped binary)
- `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` clean (0 warnings).
- `regression.ps1 -Dataset Stellar` mode1/2/3: the default (`percolator`) stays
  byte-identical to the committed golden (no golden re-capture for Part A). A mode that
  changes output must be behind the non-default selector.
- **Entrapment oracle (the real gate):** Stellar 3-file libdecoy, precursor, the
  `transfer`/`tric` mode must return to ~0.90% combined FDP while retaining the pass-2
  re-scoring ID gain. Harness above; reference numbers in this file.

## References
- [[project_osprey_pass2_recalibration_inflates_fdr]] (the root finding),
  [[project_osprey_pass2_gate_divergence]], [[project_osprey_natural_entrapment]],
  [[project_osprey_libdecoy_vs_gendecoy_calibration]]
- `completed/TODO-20260701_osprey_separate_protein_reporting_from_rescue.md`
  (oracle A/B/C/E, decoy-depletion mechanism, variant catalogue, prototype pointers)
- Related backlog: [[TODO-osprey_assumption_failure_detection.md]] (shared
  decoy-independent null reference -- its Section A build-once null is reusable here),
  `TODO-osprey_reduced_pool_fdr_calibration.md`
- Prototypes: branch `Skyline/work/20260704_osprey_pass2_recalibration` @ `d52cf7db17`
  (`OspreyEnvironment.cs` + `Pass2FdrSidecar.cs`)
- Paper: `ai/.tmp/nmeth.3954.pdf` (Roest 2016, TRIC = PMC5008461)
- Evidence: `ai/.tmp/pr2-oracle-finding.md`;
  `D:\test\osprey-runs\_mdiag\stellar\stellar.model-diagnostics.html` (#4395 binary,
  no-`--protein-fdr`, Pass 1 0.90% vs Pass 2 1.47%)
- Code sites: `Osprey.Tasks/MergeNodeTask.cs` (2nd-pass gate,
  `AnyReconciledParquet`), `Osprey.Tasks/Pass2FdrSidecar.cs` (`ComputeAndPersist`),
  `Osprey.Core/OspreyEnvironment.cs` (new `OSPREY_PASS2_QVALUE`)
