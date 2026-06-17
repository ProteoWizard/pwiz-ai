# TODO-20260617_ospreysharp_debt_paydown_pr5.md -- OspreySharp debt-paydown PR 5 (move FDR orchestration into OspreySharp.FDR)

## Branch Information
- **Branch**: `Skyline/work/20260617_ospreysharp_debt_paydown_pr5` (to be created)
- **Base**: `master` (after PR 4 #4310 merged as 42bab53085)
- **Created**: 2026-06-17
- **Status**: Pre-work DONE (cross-impl audit + expanded gate, no drift found); PR 5 feature work (FDR-ownership move) NOT started
- **PR**: (pending)

> PR 5 of the OspreySharp OOP debt-paydown arc. Seeded by the 2026-06-17 blind
> `/pw-oop-review` (`ai/.tmp/20260617-oop-review-report.txt`) plus the informed
> verdict from the session that shipped PR 4. Headline finding: FDR orchestration
> physically lives in the Tasks project, not in OspreySharp.FDR -- fragmenting
> ownership and breeding duplication.

## Framing -- the only gate is output-invariance
Decompose freely via PURE CODE MOTION, output-locked by the committed golden
(`regression.ps1` @1e-9, already Rust-free). Nothing is structure-locked; the
Rust-shaped methods are porting residue, NOT a protected shape -- "still monolithic"
means "not done yet," not "off-limits." See
`feedback_refactor_gate_output_not_structure`.

## Verdict-adjusted sequence (reordered from the review's 1->2->3)
Do the FDR-ownership move BEFORE extracting collaborators from the FDR giants, so
RunPercolator's collaborators land in their final home instead of being carved in
Tasks and moved next PR.

### Phase A -- scoping spike: sever ctx / Environment.Exit from FDR orchestration
The real cost of the move (the review's "one focused PR" undersells this; it is NOT
the diagnostics seam, which is already clean). FDR orchestration (`RunPercolatorFdr`,
`RunSimpleFdr`, the protein-FDR glue in FirstJoinTask / MergeNodeTask /
PerFileRescoreTask) currently:
- takes `PipelineContext` (lives in Tasks; OspreySharp.FDR cannot depend on Tasks --
  that is the cycle), and
- has `OspreyDiagnosticsLog.ExitAfterDump` (an `Environment.Exit`) interleaved into
  the control flow.
Spike deliverable: a concrete cut-list -- what an engine takes instead of `ctx` (the
byproduct data + `IOspreyDiagnostics` from OspreySharp.Diagnostics), and how the
dump/early-exit inverts (engine RETURNS a signal; the Tasks-layer caller decides to
`Exit`). Confirm the `FDR -> Diagnostics` dependency is acyclic. No behavior change.

### Phase B -- move FDR orchestration into OspreySharp.FDR
Introduce `PercolatorEngine` (owns RunPercolatorFdr / RunSimpleFdr / streaming) and
`ProteinFdrEngine` (owns first-pass/second-pass protein FDR now split across three
tasks). Tasks call a thin facade; the FDR project owns FDR. The single move also:
- removes the encapsulation leak (FirstJoinTask reaching `PercolatorFdr`'s
  promoted-public internals `BuildTrainingSubset` / `SubsampleByPeptideGroup` --
  demote them to internal once the caller is in-project), and
- removes the protein-FDR duplication across the three tasks.
Pure code motion; byte-identical after each commit.

### Phase C -- consolidate duplicated FDR math (fold into B)
- Unify the 4 near-identical q-value methods behind one core (allocating vs
  scratch-pooled as overloads).
- Reconcile the two target-decoy competition impls (`FdrController.CompeteAndFilter<T>`
  vs `PercolatorFdr.CompeteFromIndices`) -- one core, or a documented why-two.
- NOTE: `FdrController` is NOT dead (live for `--fdr-method simple`,
  `FirstJoinTask.RunSimpleFdr`, has FdrTest.cs). The blind review's sub-agent was
  wrong; the review itself corrected it. Do not delete.

## Out of scope (future tranches)
- **Extracting collaborators from the giant methods** (`CoelutionScorer.ScoreCandidate`
  ~827, `PercolatorFdr.RunPercolator` ~441, `RescoreOneFile`, `PlanStage6`) -- review
  Rec 1. The next tranche AFTER FDR has its home (PR 6+). Output-locked pure motion
  when they come up; nothing keeps them whole but order-of-operations + size.
- **AbstractScoringTask** inheritance-for-sharing -> composed Scoring collaborator
  (review open question; `DeduplicateDoubleCounting` is feature-envy on a task base).
  Architectural fork to decide before moving those helpers; defer.
- **Thin-exe** (old candidate B): cosmetic; the blind review did not even rank it.
  Parked.

## Gates (standing OspreySharp cadence)
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (modes 1 & 2 byte-identical).
- Pre-merge: `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar`
  + `/pw-self-review`, then open PR, Copilot, `/pw-respond`.

## Pre-work (2026-06-17): deep cross-impl parity audit -- FINDINGS
Ran the resurrected boundary-walk bisect driver (archive copy patched into
`ai/.tmp/Bisect-Crossimpl.ps1`) on Stellar 3-file: Rust osprey 26.6.1 vs current
C# OspreySharp, stage-ordered.

**Headline: the debt-paydown refactor did NOT break parity.** The C# golden held
byte-identical every run across the whole arc (blib 52,514,816 B), so C# output is
frozen by the refactor; any Rust-vs-C# gap predates the arc or is from Rust.

**Endpoint cross-impl parity still holds at <=1e-9:**
- Stage 7 protein FDR: PASS (best_peptide_score max_diff 1.6e-11).
- blib: every numeric column PASS (EndRT/ApexRT 3.6e-15, IntegratedArea 7.9e-10,
  ApexIntensity exact). The ONLY blib FAIL is `OspreyMetadata.osprey_version`
  (rust 26.6.1 vs cs 26.1.1.167) -- expected, C# is on the Skyline version scheme.

**Interim byte/SHA FAILs are mostly above the 1e-9 bar (never the real gate):**
- calibration.json / reconciliation.json: cross-language JSON float formatting
  (calibration also differs in SIZE ~3% -- C# digit width); .fdr_scores.bin: SHA
  differs at identical sizes (ULP-level f64). None are 1e-9 numeric divergences.

**The one substantive interim divergence: `scores.parquet` ROW COUNT** -- rust 463080
vs cs 462802 (278 rows, 0.06%), Stage 6 reconciled parquet. Does NOT reach the
endpoint (Stage 7 + blib numerics match). Likely a decoy/gap-fill-region row-count
difference that is endpoint-neutral. New-vs-pre-existing is UNKNOWN: the maintained
cross-impl gate only ever checked Stage 7 + blib at 1e-9 (never parquet row count),
so it was below the radar; cannot tell without a port-time Rust baseline.

**Context:** Rust osprey is ARCHIVED (relicensed LGPL + "archived in favor of
OspreySharp", 2026-06-03; last commit 2026-06-10). So cross-impl is a frozen,
retired reference -- chasing exact cross-impl bit-parity against it is low-value.

### BASELINE ESTABLISHED (2026-06-17) -- a56498ca78 control, net8.0, frozen Rust
Promoted the boundary-walk script to first-class (`Compare/Compare-EndToEnd-Bisect-Crossimpl.ps1`,
`-Framework` net8.0, `-CsExe/-RustExe` overrides) and ran C#@a56498ca78 (net8.0) vs
the frozen Rust reference. Rust is unchanged since a56498ca78 (post-commits are CLI
#47 + relicense, non-algorithmic), so this is a clean control.

**The true parity bar at a56498ca78** (what actually held cross-impl):
- reconciliation.json: **byte-equal** (sha-identical to Rust, all 3 files).
- scores.parquet: **PASS** -- 463080 rows == Rust, all 40 cols within 1e-9.
- stage7: PASS (1e-9). blib: PASS (1e-9, version string matched then).
- calibration.json + .fdr_scores.bin: FAIL **even at baseline** -- never byte-equal
  cross-impl (JSON float-text width / binary f64 ULP). These boundary checks are NOT
  drift detectors; only recon.json byte-equality + the 1e-9 numeric boundaries are.

**CONFIRMED DRIFT introduced by the OOP arc (framework-independent):**
- **scores.parquet ROW COUNT: a56498ca78 = 463080 (== Rust); current = 462802 (-278).**
  Row count does not depend on float formatting, so this is unambiguous behavior
  drift in Stage 6 reconciled-parquet emission. Endpoint-neutral (stage7 + blib still
  1e-9), which is exactly why the endpoint golden never caught it. This corrects the
  earlier "not a refactor regression" read -- it IS arc-introduced drift.

**SUSPECTED DRIFT (needs the framework-matched current net8.0 run to separate from a
net472 cosmetic):** reconciliation.json -- byte-equal to Rust at baseline, byte-differs
in today's run (which was net472).

**Next:** (1) current C# net8.0 boundary run (framework-matched to the baseline) to
lock the slip set and confirm/clear recon.json; (2) bisect forward through the arc
commits on the 278-row parquet drop (and recon.json if real) to attribute each slip,
same method that reached a56498ca78; (3) freeze a56498ca78 boundary outputs as the
committed C#-vs-C# per-stage local golden (the durable diagnostics regression).
Do NOT retire the diagnostics -- the baseline proves they still discriminate.

## Notes
- `project_ospreysharp_diagnostics_bleed_blocks_scoring_extraction` is now PARTLY
  STALE per the blind review (scoring seam clean: lower layers see
  `IScoringDiagnostics` / `IOspreyDiagnostics`; no static call to the exe-level
  facade). Re-verify and update the memory during Phase A.

### CROSS-IMPL AUDIT RESOLVED + EXPANDED GATE BUILT (2026-06-17)
- **No drift, anywhere.** The "278-row scores.parquet" was NOT a regression: commit
  #4261 ("Stopped Stage 6 from overwriting the Stage 4 scores parquet") changed what
  scores.parquet HOLDS (Stage-4 462802 now; reconciled 463080 moved to
  .scores-reconciled.parquet). Rust still overwrites in place, so the old end-to-end
  walk compared Rust-reconciled vs C#-Stage-4. Proof: a56498ca78 Stage-4 (`--no-join`)
  = 462802 = current Stage-4. Every other boundary diff was timestamp / Rust-only
  diagnostics / ULP / compression-codec / intentional `osprey_version`.
- **Stable Rust reference set** built by `Compare/Build-CrossImplReference.ps1`
  (two passes: `--no-join` freezes Stage-4 parquet, straight-through freezes
  reconciled + side-cars + Stage7 + blib), at `D:\test\osprey-runs\stellar\_crossimpl_reference\`
  with a README (Rust 696c938 / v26.6.1). Not committed (large); regenerate locally;
  PanoramaWeb someday.
- **Expanded occasional gate** `Compare/Compare-CrossImpl-Reference.ps1`: OspreySharp
  live vs frozen reference, stage-correct (C# Stage-4 scores.parquet -> ref
  .scores.stage4.parquet @1e-9), reconciliation.json byte-equal, `.bin` value-level
  (`bin_tol_diff.py`), Stage7 + blib @1e-9 (`osprey_version` whitelisted in
  Compare-Blib-Crossimpl). calibration.json dropped (bisection-debug artifact).
  **Ran net8.0: OVERALL PASS, all 14 boundaries green.** regression.ps1 stays the
  everyday gate; this is the periodic cross-impl double-check.
- **BACKLOG (minor product bug surfaced):** `OspreyFileDiagnostics.WriteCalibrationSummary`
  writes a hardcoded `cs_cal_summary.txt` (no per-file stem), so diagnostics-on +
  multi-file parallelism (default `min(nFiles, cores)`) collide on it ("file in use").
  Gate works around it with `OSPREY_MAX_PARALLEL_FILES=1`. Fix: per-stem filename
  (or skip when file-parallel). Diagnostic-only; does not affect output.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260617_ospreysharp_debt_paydown_pr5.md` before starting work.
