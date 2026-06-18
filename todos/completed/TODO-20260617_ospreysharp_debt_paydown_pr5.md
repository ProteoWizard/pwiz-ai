# TODO-20260617_ospreysharp_debt_paydown_pr5.md -- OspreySharp debt-paydown PR 5 (move FDR orchestration into OspreySharp.FDR)

## Branch Information
- **Branch**: `Skyline/work/20260617_ospreysharp_debt_paydown_pr5` (to be created)
- **Base**: `master` (after PR 4 #4310 merged as 42bab53085)
- **Created**: 2026-06-17
- **Status**: Completed
- **PR**: [#4314](https://github.com/ProteoWizard/pwiz/pull/4314) (merged 2026-06-18 as 3c464c983b)

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

## Phase A DELIVERABLE (2026-06-17): the cut-list -- DONE
Spike complete. Read the four FDR-orchestration methods + every call site +
the project-reference graph. **Headline: the coupling is far thinner than the
review feared, and the dependency direction *forces* the dump-stays-in-Tasks
inversion -- it is required, not merely preferable.**

### Root-cause finding: FDR -> Diagnostics is NOT acyclic (it is a back-edge)
`OspreySharp.Diagnostics.csproj` already references `OspreySharp.FDR`
(Diagnostics names FDR domain types: FdrEntry, ProteinParsimonyResult,
ReconcileAction, PeptideScore). So **FDR cannot depend on Diagnostics** -- that
would be a project-reference cycle. Consequence: the FDR engines must NOT take
`IOspreyDiagnostics`, and must NOT call `OspreyDiagnosticsLog.ExitAfterDump`
(also in the Diagnostics project). The engine RETURNS the dump payload + a
signal; the Tasks-layer facade owns the `ctx.Diagnostics?.Write...` dump and the
`ExitAfterDump` decision. This is exactly the inversion the plan called for, now
confirmed mandatory by the existing graph (not a stylistic choice).

### What each FDR-orchestration method actually touches on `ctx`
Verified by reading FirstJoinTask.cs:1218-1576. The heavy compute already takes
NO ctx (PercolatorFdr.RunPercolator / BuildTrainingSubset /
ScorePopulationAndComputeFdr / ProteinFdr.RunFirstPassProteinFdr are pure FDR
statics). The four Tasks-layer wrappers use ctx for only two things:
- `RunPercolatorFdr` (1218): `ctx.LogInfo` x9, `ctx.LogWarning` (dispatcher). NO
  Diagnostics, NO Exit, NO Get/Publish, NO ExitCode.
- `RunPercolatorStreaming` (1400): `ctx.LogInfo` x2 only.
- `RunSimpleFdr` (1475): `ctx.LogInfo` only.
- `RunFirstPassProteinFdr` (1524): `ctx.LogInfo` x2 + the ONLY diagnostics block:
  `ctx.Diagnostics?.DumpProteinFdr` / `WriteStage6ProteinFdrDump(bestScores,
  proteinFdr.PeptideQvalues)` / `ProteinFdrOnly` -> `ExitAfterDump` (1569-1575).
The byproduct registry (Get/Publish) and ExitCode are touched by the *surrounding*
FirstJoinTask.Run / Stage-6 planning code (445-803), which STAYS in Tasks. The
engine boundary is clean.

### The cut-list (what each engine takes instead of `ctx`)
- **Logging** -> `Action<string> logInfo` (+ `logWarning` for the dispatcher
  default-case). Established pattern: `new CoelutionScorer(ctx.LogInfo,
  ctx.Diagnostics as IScoringDiagnostics)` (AbstractScoringTask.cs:321). Pure
  delegate, zero project dependency.
- **Config** -> `OspreyConfig` directly (already in OspreySharp.Core, which FDR
  references). No change.
- **Diagnostics + early-exit** -> NOT passed to the engine. `ProteinFdrEngine`
  returns the first-pass result (parsimony + `bestScores` + `proteinFdr` incl.
  `PeptideQvalues`); the Tasks facade keeps the `DumpProteinFdr` block and the
  `ProteinFdrOnly -> ExitAfterDump` decision. (`ProteinFdr.RunFirstPassProteinFdr`
  already returns enough; the wrapper's recompute of parsimony/ComputeProteinFdr
  for the dump can fold into the engine's returned result.)
- **PIN feature plumbing** -> the engine takes feature names/count as inputs, it
  does NOT reach the IO/Scoring constants. `ParquetScoreCache.PIN_FEATURE_NAMES`
  (OspreySharp.IO) and `NUM_PIN_FEATURES = OspreyFeatureCalculators.FeatureCount`
  (Scoring, via AbstractScoringTask) are NOT reachable from FDR (FDR refs only
  Core/ML/Chromatography). Resolution: the facade supplies `FeatureNames` via the
  existing `PercolatorConfig.FeatureNames`, and `PercolatorEntryBuilder.Build`
  takes `expectedFeatureCount` as a parameter. Keeps FDR's reference surface
  unchanged -- no new project refs, no new cycle.

### Code-motion inventory for Phase B (all pure motion, output-locked)
- Move into `OspreySharp.FDR`: `PercolatorEntryBuilder` (Tasks, internal static;
  parameterize the feature count), the bodies of `RunPercolatorFdr` /
  `RunPercolatorStreaming` / `RunSimpleFdr` -> `PercolatorEngine`, and the
  `RunFirstPassProteinFdr` wrapper logic -> `ProteinFdrEngine`.
- Demote to `internal` once callers are in-project: `PercolatorFdr.BuildTrainingSubset`
  and `SubsampleByPeptideGroup` (the promoted-public leak; sole external caller is
  RunPercolatorStreaming at FirstJoinTask.cs:1426).
- **Call sites to rewire** (the only cross-task consumer): `Pass2FdrSidecar.cs:203`
  calls `FirstJoinTask.RunPercolatorFdr(perFileEntries, config, ctx, "Second-pass")`.
  Repoint to the new engine via the thin facade, passing `ctx.LogInfo`. All other
  callers (`RunFdr` dispatcher 1194/1198/1205, `RunFirstPassProteinFdr` 230) are
  FirstJoinTask-internal.
- The `RunFdr` dispatcher (switch on `config.FdrMethod`) stays in Tasks as the
  facade entry; it delegates to `PercolatorEngine`/`FdrController`.

### Acyclicity confirmation
Post-move graph stays acyclic: FDR -> {Core, ML, Chromatography} unchanged
(engines add only `System` + `Action<string>`); Diagnostics -> FDR back-edge
preserved; Tasks -> {FDR, Diagnostics, ...} unchanged. No FDR -> Diagnostics and
no FDR -> Tasks edge is introduced. **Confirmed safe.**

### Memory re-verify (TODO Notes item)
`project_ospreysharp_diagnostics_bleed_blocks_scoring_extraction` is about the
Scoring layer (clean via `IScoringDiagnostics`). The FDR equivalent is different:
the blocker is the **FDR<-Diagnostics project back-edge**, resolved by the
return-the-payload inversion above (no IOspreyDiagnostics in FDR). No memory edit
needed; captured here.

## Phase B PROGRESS (2026-06-17) -- branch created, commits landing
Branch `Skyline/work/20260617_ospreysharp_debt_paydown_pr5` off master @42bab53085.
Baseline (pre-change) regression confirmed byte-identical (blib 52,514,816). Each
commit below: Build Debug -RunTests -RunInspection (0 warnings, 390 pass) +
regression Stellar mode1+mode2 byte-identical.
- **Commit 1 (86e2709cb0):** Introduced `PercolatorEngine` (OspreySharp.FDR) owning
  RunPercolatorFdr + streaming; `FirstJoinTask.RunPercolatorFdr` now a thin facade
  passing `ctx.LogInfo` + PIN feature names. Moved `PercolatorEntryBuilder` into FDR
  (feature count parameterized -> no Scoring/IO constant reach). PASS.
- **Commit 2 (cb030f7980):** Moved `RunSimpleFdr` into PercolatorEngine; dispatcher
  calls engine with `ctx.LogInfo`. Demoted `PercolatorFdr.BuildTrainingSubset` +
  `SubsampleByPeptideGroup` public->internal (encapsulation leak gone; sole external
  caller was the now-in-project streaming path). PASS.
- **Commit 3 (64a849c588):** `ProteinFdr.RunFirstPassProteinFdr` now RETURNS a
  `FirstPassProteinFdrResult` (detected/parsimony/bestScores/proteinFdr); the
  FirstJoinTask facade logs + dumps from it instead of recomputing parsimony +
  ComputeProteinFdr a second time. Removes the first-pass protein-FDR recompute
  duplication. The dump/ExitAfterDump stays in the Tasks facade (FDR<-Diagnostics
  back-edge, per Phase A). PASS.
- **Commit 4 (Phase C, c3052b42db):** Unified the 3 near-identical q-value methods
  (`ComputeConservativeQvalues` / `ComputeQvalues` / `ComputeQvaluesInto`) behind
  one `ComputeQvaluesCore(isDecoy, qValues, n, decoyOffset)` -- they differed only
  by the +1 conservative offset and the prefix length; `scores` was vestigial in
  all three. Documented the two competition impls (`CompeteFromIndices` hot/array
  path vs `FdrController.CompeteAndFilter<T>` generic) as a deliberate why-two
  (perf vs ergonomics, same competition rule), not a duplicate to merge.

**Reframed scope note:** the Percolator *move* (the review's headline ownership
fragmentation -- RunPercolatorFdr physically in Tasks) is DONE in commits 1-2.
`ProteinFdr` already lived in OspreySharp.FDR, so the protein side is de-duplication
(commit 3), not a move. Phase C q-value unification = commit 4. The cross-task
ProteinFdrEngine consolidation (FirstJoin first-pass + MergeNode second-pass +
PerFileRescore rehydration share one shape) is a candidate follow-up tranche (PR 6),
lower value than what landed here.

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

### 2026-06-18 - Merged

PR #4314 merged as commit 3c464c983b. Shipped the FDR-ownership move (Phase B)
and the q-value/competition consolidation (Phase C) as 4 byte-identical commits:
PercolatorEngine + the streaming/simple moves into OspreySharp.FDR behind a thin
FirstJoinTask facade; the first-pass protein-FDR return-value inversion that drops
the recompute; the BuildTrainingSubset/SubsampleByPeptideGroup public->internal
demotion; and the single ComputeQvaluesCore. Phase A's finding stands: the
FDR<-Diagnostics project back-edge forces the dump + ExitAfterDump to stay in the
Tasks facade. Gates: per-commit build/inspection/390-tests + Stellar golden;
pre-merge regression -Dataset All (Stellar + Astral) + perf gate (stage5 flat);
fresh-context self-review clean. Deferred to a later tranche (PR 6+): the
cross-task ProteinFdrEngine consolidation (FirstJoin/MergeNode/PerFileRescore share
one shape) and extracting collaborators from the giant scorer methods. Copilot's 3
`scores`-unused comments were intentionally declined (no warning; pre-existing
signature symmetry / debugging aid) and left unresolved for the human reviewer.
Backlog still open: cs_cal_summary.txt per-stem filename fix (diagnostic-only).
