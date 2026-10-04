# Retire Osprey's parity-only code paths - the central catalogue

**Status**: Backlog, living catalogue. Started 2026-10-04 (Brendan) during PR #4765 (FirstPassFDR on the i9).
**Related**: [TODO-osprey_env_var_cataloging.md](TODO-osprey_env_var_cataloging.md) catalogues the env
switches we KEEP (for `--help-env`); this file tracks the ones that exist only for parity testing and must
eventually be REMOVED. `pwiz_tools/Osprey/docs/00-pipeline-architecture.md` holds the memory principles.

## Why this exists

The pipeline was rewritten so memory stays bounded as the file count grows. Switches and fallbacks that
keep the old paths alive - above all the ones that rebuild O(files x precursors) resident structures - were
retained so the new paths could be checked for parity. Each is a maintenance cost and, where it re-enables
unbounded memory, a hazard. They all need to go; this file is where that work is tracked.

## Rule for every session

**Adding a switch whose only purpose is parity with a superseded path (an env var, a CLI flag, a code
constant, or a default-OFF arm left behind when a default flips)? Add a row to the table below in the same
change.** Removing one? Delete its row and section in the same change. Keep evidence as `file:line` on the
port branch.

---


- Checkout: `C:\proj\pwiz-work1` (branch `Skyline/work/20260930_osprey_pass2_runq_reuse`).
- Scope: `pwiz_tools/Osprey` only. All paths below are relative to that folder unless they start with `ai/scripts/Osprey` (which means `C:\proj\ai\scripts\Osprey`).
- Initial inventory: a read-only sweep on 2026-10-04; line numbers are as of that date.
- Line counts are rough and include doc comments.
- **(inferred)** marks a conclusion reached by reading code, not by running it.

Categories:
- **A**: a parity or legacy path for a superseded implementation. These are the removal candidates.
- **A\***: not driven by a switch, but it brings back O(files) or O(files × precursors) memory, so it belongs in this catalogue.
- **B**: a diagnostic or measurement harness.
- **C**: a genuine user or operator setting.

## Summary table

| # | Switch / mechanism | Cat | Memory impact of the old arm | Main files | Removal blockers | Rough lines that go |
|---|---|---|---|---|---|---|
| A1 | `OSPREY_FDR_PROJECTION=0` (resident FdrEntry first pass) | A | **O(files × precursors)**: the whole pre-compaction stub pool, with features (~0.8 GB/file) | PerFileScoringTask, FirstPassFdrTask, Osprey.FDR PercolatorEngine / PercolatorEntryBuilder / PercolatorScorer, ResidentPaths | The Stage-5 Percolator dump (`OSPREY_DUMP_PERCOLATOR`) only works on this arm; 5 FdrTest oracle tests; docs call it "the oracle" | ~1,000 prod + ~500 test |
| A2 | `OSPREY_STAGE6_STREAM_SURVIVORS=0` (resident post-compaction survivor buffer) | A | **O(files × survivors)**: 28 GB at 163 files, super-linear | FirstPassFdrTask, PerFileRescoreTask, PerFileScoringTask guard, OspreyEnvironment, ResidentPaths | Pin test in ResidentPoolGuardTest; docs only | ~170 + ~70 test |
| A3 | Resident Stage-7 join (`RescoredEntries.Streams == false`), reached from A1, A2 **and** A4 | A (shared) | **O(files × survivors)**: 4.4 GB + 0.197 GB/file; 91.1 GB measured at 446 runs | Pass2FdrSidecar, SecondPassFdrTask, PerFileRescoreTask, PipelineByproducts | Goes only after A1, A2 **and** A4's per-file half have all moved | ~300 |
| A4 | `OSPREY_PASS2_QVALUE=transfer`: per-file half computed in Stage 7 over the whole pool (#4665) | A (placement) / C (algorithm) | **O(files × survivors)** via A3 | Pass2FdrSidecar (transfer core ~540, ComputePass2Resident 154), Program.cs | Transfer is the **only** pass-2 mode compatible with `OSPREY_EXPERIMENT_AGG=mean-best-N`; the plan is to MOVE `TransferOneFile` into `Pass2PerFileWorker`, not delete it | ~250 resident glue (the algorithm stays) |
| A5 | `OSPREY_RELEASE_LIBRARY_FRAGMENTS=0` | A | O(library), not O(files): +10.8 GB at 4 SEA-AD files | LibraryFragmentRelease, OspreyEnvironment, LibraryEntry tripwire text | Two tests to rework; =0 not honoured on the `--task SecondPassFDR` leg (inferred inconsistency) | ~70 + ~60 test |
| A6 | `OSPREY_ALLOW_UNFIXED_RESIDENT` + `ResidentPaths` + resident-pool guards | A (support) | n/a (it admits A1/A2) | OspreyEnvironment 390-470, ResidentPaths.cs, PerFileScoringTask guards, Program.cs, regression.ps1 | Goes after A1 and A2 | ~350 prod + ~450 test + ~60 ps1 |
| A7 | Diagnostics that force resident pools: `OSPREY_DUMP_PERCOLATOR`, `DUMP_RESCORED`, `DUMP_MULTICHARGE` / `DUMP_RECONCILIATION`, all enabled by `-d` | B\* | **O(files × precursors)**, warn-only, no guard | PerFileScoringTask.PreCompactionPoolReason, PerFileRescoreTask, Stage6Planner | Rust cross-impl bisection workflow (Test-Snapshot stage5, DIAGNOSTICS.md) | redesign, not delete |
| A8 | Unswitched resident fallbacks: full `FdrProjectionSet.BuildFromEntries`, all-runs `HydrateReconciliationOverlay`, the disk-state reasons in `PreCompactionPoolReason` | A\* | **O(files × precursors)** on resume / recon-sidecar routes | FirstPassFdrTask:3188, RescoreHydration:320-497, PerFileScoringTask:1785-1827 | These are live resume paths; each needs a streaming replacement | ~300 once streamed |
| A9 | `OSPREY_LOESS_CLASSICAL_ROBUST=0` (legacy cached-residual LOESS) | A | none | LoessRegression, RTCalibration, Calibrator, CalibrationRefit | Rust v26.3.1+ matches the default; none known | ~15 |
| A10 | `OSPREY_PICK_LDA=0` (legacy product-form peak pick) | A | none | PeakDataExtractor, OspreyEnvironment (validity key) | Scripts expose `-PickProduct`; doc says "kept precisely so the two stay comparable"; Rust may still pick by product (inferred) | ~25 + scripts |
| A11 | `OSPREY_TRAIN_PICK_RUN=0` (cross-run maximum training row) | A | none (same dictionaries) | PercolatorSampling, PercolatorScorer, validity key | Rust's criterion is the maximum, so a cross-impl comparison needs it (inferred) | ~30 |
| A12 | `OSPREY_MAX_PARALLEL_FILES` (back-compat cap) | A | none (a cap, not a memory path) | FileParallelism.cs:87-163, PerFileScoringTask:1078 | `ai/scripts/Osprey/Test-PerfGate.ps1` uses it as the cross-binary control for a baseline binary that predates `--parallel-files` | ~25 + tests |
| A13 | Retired-name stubs: `OSPREY_STAGE7_STREAM` refusal; `OSPREY_ALLOW_UNBOUNDED_MEMORY`, `OSPREY_PROTEIN_COMPACT_RETRAIN`, `OSPREY_EXIT_AFTER_SCORING` comments; the `transfer-compete` / `percolator` names | A (residue) | none | Program.cs:579-595, OspreyEnvironment:290-307, scripts' ValidateSets | Stale scripts still pass them; the refusal protects A/B attribution | ~35 code + comments |
| A14 | `OSPREY_BLOCK_READ_MB=0` (default 4 since 2026-10-04, PR #4765) | A | none | BlockReadStream.OpenRead | None once the default flips; keep BlockReadStats/Log as B | ~5 |
| A15 | `OSPREY_BLOCK_READ_GATE=0` (default on since 2026-10-04, PR #4765) | A | none | BlockReadStream.ReadFromDisk | none | ~5 |
| A16 | `OSPREY_STUB_IDENTITY=0` (default 1 since 2026-10-04, PR #4765) | A | none (LibraryIdentity is O(library)) | ParquetScoreCache 1145-1500, FirstPassFdrTask 208, 4225-4335, FirstPassSurvivorLoader:121 | The decode-from-file path is **not** removable; it is the per-row-group fallback when the library lacks an id. Only the mode switch and the `=2` verifier go | ~40 |
| A17 | Old-format back-compat readers | A (back-compat) | none | FirstPassModelIO StratumBaseIds, ParquetScoreCache reconciled="true", CalibrationParams legacy JSON | Pre-split output directories would stop resuming | ~60 |
| A18 | Dead or test-only code found along the way | cleanup | none | FdrProjection.cs Builder, FdrProjectionSinks FdrStreamingSink, PercolatorQValues, PercolatorEngine frozenModel | none | ~300 |

Rough total if every A item is fully removed: about 3,000 production lines and 1,200 test lines. The largest single block is A1. The Rust-bisection diagnostics family (`OspreyFileDiagnostics.cs` and related) is about 3,400 lines, but it is category B and is not counted.

---

## Category A details

### A1. `OSPREY_FDR_PROJECTION=0`: the resident FdrEntry first-pass path

- **How set:** environment variable. `OspreyEnvironment.UseFdrProjection` (`Osprey.Core/OspreyEnvironment.cs:244-264`), `IsNotZero`. It is a settable property so tests can flip it.
- **Default:** ON (streaming). `=0` selects the legacy arm.
- **Why kept:** "Set OSPREY_FDR_PROJECTION=0 ONLY to force the legacy FdrEntry-buffer path as a transitional A/B / byte-identity oracle. ... this oracle is the legacy path's only remaining user." The legacy path "OOMs" at real file counts (same doc comment).
- **Gate:** `PerFileScoringTask.NeedsResidentPool(config, useFdrProjection)` returns `!useFdrProjection` and nothing else (`Osprey.Tasks/PerFileScoringTask.cs:2269-2290`). Token: `ResidentPaths.PROJECTION_OFF` (`Osprey.Core/ResidentPaths.cs:83-98`).
- **Memory:** O(files × precursors). Every file's pre-compaction stubs, with features, stay resident across first-pass Percolator, protein FDR, the sidecar write and compaction.

**Code that exists only for this arm:**

| Code | file:line | ~lines |
|---|---|---|
| `NeedsResidentPool` (both overloads) | PerFileScoringTask.cs:2227-2290 | 64 |
| `GuardResidentPool`, `ResidentPoolGuardError`, `ResidentPoolTrigger` | PerFileScoringTask.cs:2319-2394, 2446-2480 | 110 |
| `Run` fat load (`scored-entries: resident`) | PerFileScoringTask.cs:406-471 | 60 |
| `RehydrateFromOwnOutputs` fat branch | PerFileScoringTask.cs:757-801, 924-929 | 50 |
| `TryLoadStubsAndCalibration` strict arms | PerFileScoringTask.cs:2593-2611 | 10 |
| `LoadJoinOnlyScores` features branch | PerFileScoringTask.cs:1464-1486, 1648-1665 | 30 |
| `PreCompactionPoolReason` term | PerFileScoringTask.cs:1798-1799 | 2 |
| `FirstPassFdrTask.Run` legacy branch | FirstPassFdrTask.cs:667-820 | 150 |
| `RunPercolatorFdr(List<FdrEntry>)` facade | FirstPassFdrTask.cs:2826-2897 | 72 |
| `RunFirstPassProteinFdr` | FirstPassFdrTask.cs:2960-3003 | 44 |
| `WriteFdrScoresSidecars` | FirstPassFdrTask.cs:2369-2464 | 96 |
| `WriteFdrBenchPass1IfRequested` (resident FDRBench emitter) | FirstPassFdrTask.cs:1912-1944 | 33 |
| `CompactFirstPass` non-bundle branch | FirstPassFdrTask.cs:2130-2189 | 60 |
| `RehydrateForPerRunRescore` resident-stub guard | FirstPassFdrTask.cs:1222-1257 | 36 |
| `LoadOwnReconciliationBundle` resident arm | FirstPassFdrTask.cs:1373-1452 (parts) | 40 |
| `PercolatorEngine.RunPercolatorFdr(List<FdrEntry>)`, `DispatchSvm`, `ApplyPercolatorResults`, `RunPercolatorStreaming` (PercolatorEntry list) | Osprey.FDR/PercolatorEngine.cs:61-205, 488-724 | 380 |
| `PercolatorEntryBuilder.cs` | whole file | 194 |
| `PercolatorScorer.ScorePopulationAndComputeFdr` | Osprey.FDR/PercolatorScorer.cs:88-269 | 180 |
| Stage-7 admission term | ScoringTaskShared.cs:867-868 | 2 |

Smaller simplifications:
- `CanUseLeanProjection` loses its first term (PerFileScoringTask.cs:2292-2317).
- `LibraryFragmentRelease.RunsOnThisLeg` reduces to `true` for the projection term (LibraryFragmentRelease.cs:63).
- `ModelDiagnosticsReport.Write` (the batch write, `ModelDiagnostics/ModelDiagnosticsReport.cs:104-~170`) is mostly reached only from here (FirstPassFdrTask.cs:1741). It may also be reached by a batch-hydrate rehydrate (inferred).

**What stays:**
- `FdrEntry` itself: every field is still used by per-file resume, Stage 6/7, the survivor loader and transfer.
- The shared mean-best floor estimator (TargetDecoyCompetition.cs:366-543).
- `HydrateReconciliationOverlay` (see A8).
- The non-counts-only `FdrProjectionSet.BuildFromEntries` arm (see A8).

**Tests that exercise it:**
- `Osprey.Test/ResidentPoolGuardTest.cs:56-284`: token naming, `KNOWN_UNFIXED` pin at 217-222, `NeedsResidentPool(...,false)` at 253, `CanUseLeanProjection(...,false)` at 143. `PROJECTION_OFF` is also used as a sample token at 373-448; those need a substitute.
- `Osprey.Test/FdrTest.cs` oracle tests: 833, 1164, 1242 (calls the FdrEntry overload at 1266), 1298, 3436 (helper 3469-3474).
- `Osprey.Test/PercolatorEntryBuilderTest.cs` (whole file).
- `Osprey.Test/LibraryFragmentReleaseTest.cs:176-235`.
- `Osprey.Test/SubsetPipelineTest.cs:346,348` assert the resident route lines are absent.

**regression.ps1:** never sets it and has no mode for it. It only reads it:
- :434-458 keeps an inherited allowance token when `=0` is set.
- :2235-2244 `$cannotStreamJoin`.
- :427-429 describes it as a "by design" oracle.

**Scripts:** nothing under `ai/scripts/Osprey` sets it.

**Blockers:**
1. **The Stage-5 Percolator dump.** `OSPREY_DUMP_PERCOLATOR` / `OSPREY_PERCOLATOR_ONLY` on a straight-through run work only on this arm. The default path warns and tells the user to re-run with `OSPREY_FDR_PROJECTION=0 OSPREY_ALLOW_UNFIXED_RESIDENT=projection-off` (FirstPassFdrTask.cs:1653-1699; verified at 1670-1682). The cross-impl bisection docs rely on this dump: docs/15-hpc-scoring-split.md:197, docs/18-peptide-trace.md:169,232, ai DIAGNOSTICS.md:169-174. `Test-Snapshot.ps1` stage5 may already silently produce no dump on defaults (inferred). Options: add a projection-path dump, drop the feature, or keep it only on the batch-hydrate route.
2. Five FdrTest oracle tests need deleting or retargeting onto the projection path.
3. Docs to update: OspreyEnvironment.cs:254-263, ResidentPaths.cs:84-97, regression.ps1:427-429, docs/07-fdr-control.md:177,183, docs/12-second-pass-fdr.md:185, docs/00-pipeline-architecture.md:1324, PercolatorEngine.cs:217,266-271.
4. No golden files depend on it. Mode 12's resident FDRBench A/B was banked on 2026-09-12 and is not re-run.

### A2. `OSPREY_STAGE6_STREAM_SURVIVORS=0`: the resident post-compaction survivor buffer

- **How set:** environment variable. `OspreyEnvironment.Stage6StreamSurvivors` (OspreyEnvironment.cs:274-288), a settable property. Token: `ResidentPaths.COMPACTED_ENTRIES_BUFFER` (ResidentPaths.cs:100-116).
- **Default:** ON (stream per file).
- **Why kept:** "That buffer is 88.9 M entries / 28 GB live at 163 files, held for the 5.5 hours of Stage 6, and it grows super-linearly in file count ... Set OSPREY_STAGE6_STREAM_SURVIVORS=0 to keep the resident buffer as the A/B byte-identity oracle."
- **Memory:** O(files × survivors), super-linear in file count. It also forces the resident Stage-7 join (A3), because `BuildRunPerRunSource` returns null without a loader (PerFileRescoreTask.cs:3041; regression.ps1:2227-2234 documents this).

**Code that exists only for this arm (~170 lines):**
- `Stage6StreamSurvivorsValidityKeySuffix`: OspreyEnvironment.cs:351-364. Its term: PerFileRescoreTask.cs:296.
- `Stage6ResidentHandoffGuardError`: PerFileScoringTask.cs:2396-2444 (49 lines).
- Guard calls: FirstPassFdrTask.cs:852-864 and 1082-1096.
- The branch at FirstPassFdrTask.cs:3979-3984.
- `ReloadFirstPassSurvivors`: FirstPassFdrTask.cs:3993-4043 (51 lines, plus 2 resx strings).
- The `StreamedSurvivorLoader` flag gate: PerFileRescoreTask.cs:2903-2912.

**What stays** (shared with A1 and with the resume-from-own-bundle route): the `loader == null` branches (PerFileRescoreTask.cs:1501, 3041, 3121, 3324), `RescoredPoolPlan.RefillOnly`, and the materialized `Stage6Planner.Plan(List<…>)` overload (Stage6Planner.cs:113-139).

**Tests:**
- ResidentPoolGuardTest.cs:86-88, 216-221 and 384-449 (`AssertStage6HandoffGuard`, ~65 lines).
- TaskValidityKeyTest.cs:637.
- No end-to-end test sets it.

**regression.ps1:** reads only, at :445-446, :2241 and :428. **Scripts:** none.

**Blockers:** none functional. Edit the pin test, and the docs at docs/00-pipeline-architecture.md:1282-1286 and Regression/README.md.

### A3. The resident Stage-7 join (shared by A1, A2 and A4)

There is no switch of its own. It runs whenever `RescoredEntries.Streams == false`. The streamed join is refused by `ScoringTaskShared.Stage7StreamAdmittedBeforeRescore` in three cases:
- `NeedsResidentPool` true (A1), ScoringTaskShared.cs:867;
- `!Pass2ProteinCompact` (A4), ScoringTaskShared.cs:899-900;
- no survivor loader (A2).

docs/00-pipeline-architecture.md:1314-1323 names only transfer, which is incomplete.

- **Memory:** O(files × survivors). regression.ps1:396-419 measures ~4.4 GB library + 0.197 GB/file post-GC, ~20 GB at 82 files, and 92.3 GB predicted vs 91.1 GB measured at 446 runs.

**Code (~300 lines):**
- `Pass2FdrSidecar.ComputeAndPersist` `!Streams` blocks: Pass2FdrSidecar.cs:303-307, 379-397, 440-445.
- `OverlayPass2OntoResidentPool` / `ReloadPass2Sidecars`: Pass2FdrSidecar.cs:560-629.
- `!Streams` branches in the frozen competition: Pass2FdrSidecar.cs:1828, 2069, 2187.
- In SecondPassFdrTask.cs: `WarnResidentStage7Join` (741-750) and the resident report arms (651-655, 852-856).
- In PerFileRescoreTask.cs: `BuildRescoredPool` (3102-3146), `MaterializeAllFromSource` (2373-2400) and `MaterializeAllResumedFiles` on resume (940-950).
- The `StreamFiles` fallback: PipelineByproducts.cs:691-697.

**Blocker:** it can go only after A1 and A2 are removed **and** transfer's per-file half has moved into `Pass2PerFileWorker` (#4665).

### A4. `OSPREY_PASS2_QVALUE=transfer`: its resident Stage-7 placement

- **How set:** environment variable `OSPREY_PASS2_QVALUE` (OspreyEnvironment.cs:687-757), re-read on each access.
- **Default:** `protein-compact`. Transfer is the alternative mode.
- **Why it matters here:** transfer computes its per-file half "in Stage 7 over the whole pool (TransferOneFile runs from TransferPerRunQ, not from Pass2PerFileWorker); resident for the whole of Stage 7" (regression.ps1:396, known gap #4665). ResidentPaths.cs:131-136: "operator-chosen and untokened ... it ends when that half moves to Pass2PerFileWorker."
- **Memory:** O(files × survivors), through A3.

**Transfer-only code (~850 lines):**
- In Pass2FdrSidecar.cs:
  - `RestorePass1Scalars`: 717-796;
  - `ComputePass2Resident`: 2429-2582. Its doc at :2434 is stale; it calls `TransferPerRunQ`, not `RunPercolatorFdr`;
  - `MapFeaturesByScoreIndex`: 2919-2934;
  - the transfer core (`TransferPerRunQ`, `TransferOneFile`, `BuildScoreToQTable`, `LookupQForScore`, `AssignPerRunQ`, …): 2936-3475, ~540 lines;
  - the `!frozenCompetition` branches at 250-259 and 284-290.
- `Program.cs:952-959`: refuses `--training-export` under transfer.
- `FirstPassFdrTask.cs:2857, 3828`: `(Pass2TransferQ || Pass2ProteinCompact)` is always true (the value normalizes to one of the two), so these collapse.

**Tests:**
- SubsetPipelineTest.cs:496-525 (transfer arm, `MeanBestN=2`).
- Pass2FdrSidecarTest.cs:63-320.
- CommandLineErrorTest.cs:149-154.
- TaskValidityKeyTest.cs:548-560.

**regression.ps1:** no leg runs transfer. It appears only in the known-gaps row (:390-420) and in `$cannotStreamJoin` (:2243).

**Scripts:**
- `Common/OspreyDatasetRun.psm1:166, 640-642, 942`. The warning at 640-642 says transfer "forces the RESIDENT first-pass pool", which is stale.
- `Run-FdrBench.ps1:142, 375-386`.
- ValidateSets in Run-AstralEntrap, Run-Chs, Run-CohortArms, Run-SeaAd and Run-Tdp43. These still offer the removed `transfer-compete`.

**Blockers (major):**
- Transfer is the only pass-2 mode compatible with mean(best-N). Pass2FdrSidecar.cs:1985-2002 refuses protein-compact after a mean-best first pass and names transfer as the fix; docs/07-fdr-control.md:731-741 says the same.
- The removal target is therefore the resident *placement*, by moving `TransferOneFile` into `Pass2PerFileWorker`. The algorithm itself is category C.

### A5. `OSPREY_RELEASE_LIBRARY_FRAGMENTS=0`

- **How set:** environment variable. `OspreyEnvironment.ReleaseLibraryFragments` (OspreyEnvironment.cs:309-349), a settable property.
- **Default:** ON.
- **Why kept:** "Set OSPREY_RELEASE_LIBRARY_FRAGMENTS=0 to keep the whole library resident as the A/B byte-identity oracle." The default measured 28.5 to 17.7 GB at Stage-7 peak on 4 SEA-AD files.
- **Memory:** O(library), not O(files). The saving shrinks as the file count grows.

**Code that exists only for =0 (~70 lines):**
- The flag term in `LibraryFragmentRelease.RunsOnThisLeg` (LibraryFragmentRelease.cs:57).
- The `;libfrag=0` suffix branch (LibraryFragmentRelease.cs:82-87). This is partly shared with A1.
- The tripwire message text in LibraryEntry.cs:191,198.

**Tests:** LibraryFragmentReleaseTest.cs:177-234; TaskValidityKeyTest.cs:606-659 (uses =0 to make the term observable).

**regression.ps1 / scripts:** neither sets it. Regression/README.md:81-88 describes a manual =0 verification.

**Notes:**
- PerFileScoringTask.cs:1128-1129 and TrainingExportWriter.cs:359 apply `RetainFragmentsFor` on `--task SecondPassFDR` without checking the flag. So =0 is not fully honoured on that leg, although the validity key still says `;libfrag=0` (inferred).
- Stale reference: ScoringTaskShared.cs:1017 cites a nonexistent `LibraryFragmentRelease.SummaryCanExist`.

### A6. `OSPREY_ALLOW_UNFIXED_RESIDENT`, `ResidentPaths` and the guards

- **How set:** environment variable, a comma- or semicolon-separated token list (OspreyEnvironment.cs:390-470).
- **Legal tokens:** `projection-off` and `compacted-entries-buffer` (ResidentPaths.cs:143-146).
- **Why it exists:** it replaced the blanket `OSPREY_ALLOW_UNBOUNDED_MEMORY` so that each resident path has to be named.
- It has no old behaviour of its own. It exists only to admit A1 and A2, so it is removable once both are gone.

**Code:**
- ResidentPaths.cs (148 lines, mostly history comments).
- OspreyEnvironment.cs:390-470 (~80 lines).
- The guards in A1/A2.
- The unknown-token warning in Program.cs:596-~620.
- regression.ps1:352-458, 3104-3107 (clear/keep/restore logic, ~60 lines).

**Tests:**
- ResidentPoolGuardTest.cs (~500 lines).
- CommandLineErrorTest.cs:51,157.
- SubsetPipelineTest.cs:1109.

**Script residue:** `ai/scripts/Osprey/SEA-AD/Measure-Stage6Rescore.ps1:300-322,485` still passes the retired token `hpc-merge`.

### A7. Diagnostics that silently re-create resident pools (B\*)

These are category B (Rust bisection harness). They are listed here because they bring back O(files × precursors) memory with only a warning, and because A1 removal depends on them.
- `OSPREY_DUMP_PERCOLATOR` is the first reason in `PerFileScoringTask.PreCompactionPoolReason` (PerFileScoringTask.cs:1789-1790, verified). On a resume / load-from-parquet route it loads every file's full stubs. It is warn-only (`WarnPreCompactionPool`, :1765).
- `OSPREY_DUMP_RESCORED` pulls the whole post-rescore pool (PerFileRescoreTask.cs:831-835).
- `OSPREY_DUMP_MULTICHARGE` / `DUMP_RECONCILIATION`: `EntriesForDump` keeps every file's entries (Stage6Planner.cs:204-221).
- `-d` / `--diagnostics` turns on 19 `OSPREY_DUMP_*` in-process (Osprey/OspreyDiagnostics.cs:51-95), so one CLI flag enables all of the above.

No test covers these resident effects.

**Recommendation:** decide per dump whether it can be emitted per file, or whether it is worth keeping at all.

### A8. Unswitched resident fallbacks (A\*)

These have no switch. They are chosen by disk state or route, but they are O(files × precursors):
1. **Full-size `FdrProjection` fallback** (32 B/row, ~6 GB at 191 M rows). FirstPassFdrTask.cs:3188-3189 does `prebuiltProjections ?? FdrProjectionSet.BuildFromEntries(...)`, used on resume and recon-sidecar routes. The default cold run uses `IsCountsOnly`.
2. **The all-runs bundle** `RescoreHydration.HydrateReconciliationOverlay` (RescoreHydration.cs:320-~497, ~180 lines). Callers: FirstPassFdrTask.cs:1423 and PerFileScoringTask.HydrateRescoreBundleIfPresent :2036/2070.
   - It is logged as `[PATH] all-runs-bundle` and guarded only partly (`ScoringTaskShared.AllRunsBundleGuardError` :978).
   - Its bounded twin `HydrateCompactedStreaming` (:548) still accumulates every run's survivors (comment at :638: "kept for the straight-through pipeline").
   - Tests: IOTest.cs:4803, 4998, 5095, ~5222; ResidentPoolGuardTest.cs:343-373; SubsetPipelineTest.cs:335,351.
3. **`PreCompactionPoolReason` disk-state reasons** (PerFileScoringTask.cs:1785-1827): "Training the first-pass Percolator model" on a resume that must retrain, and "Resuming without cross-run reconciliation files". Both load full stubs, ~0.8 GB/file with features. They are warn-only by design.

**Blockers:** these are live resume paths, so each needs a streaming replacement rather than a deletion.

### A9. `OSPREY_LOESS_CLASSICAL_ROBUST=0`: legacy single-refresh LOESS

- **How set:** environment variable (OspreyEnvironment.cs:113-121), readonly.
- **Default:** ON (classical).
- **Why kept:** "set to '0' to force the legacy single-refresh path for comparison."
- **Code:**
  - The `classicalRobust` parameter and the residual-refresh branch: Osprey.Chromatography/LoessRegression.cs:229-241, 293-298.
  - `RTCalibratorConfig.ClassicalRobustIterations`: RTCalibration.cs:54-63, 85, 157.
  - Reads at Calibrator.cs:1336 and CalibrationRefit.cs:91-97.
  - ~15 lines.
- **Note:** the LoessRegression doc (229-237) still says the default is false ("matches Rust"). The config default is true, so that doc is stale. RTCalibration.cs:187 calls `Fit` with robustness iterations 0, so the flag has no effect there.
- **Tests:** none found. **Scripts:** ai DIAGNOSTICS.md:98 documents it.
- **Blockers:** none (Rust v26.3.1+ uses classical).

### A10. `OSPREY_PICK_LDA=0`: legacy product-form peak pick

- **How set:** environment variable (OspreyEnvironment.cs:~385-411), readonly.
- **Default:** ON (learned model).
- **Why kept:** "The =0 opt-out is kept precisely so the two stay comparable."
- **Code:**
  - The selection and product branch in Osprey.Scoring/PeakDataExtractor.cs:218-241 and 324-338 (`rankScore = coelutionScore * rtPenalty * intensityWeight`).
  - The `pick=product` arm of `PickValidityKeySuffix` (OspreyEnvironment.cs:1040-1060).
  - ~25 lines.
- **Note:** the comment at PeakDataExtractor.cs:219-226 still says the product form is the DEFAULT, which is stale.
- **Tests:** TaskValidityKeyTest.cs:542.
- **Scripts:** `-PickProduct` in Common/OspreyDatasetRun.psm1:123-135, 612, 943 (always exports the variable both ways); Run-FdrBench.ps1; SEA-AD and TDP43 runners.
- **Blockers:**
  - The script switch.
  - Possibly Rust cross-impl parity, if Rust still picks by product (inferred; not checked in maccoss/osprey).
  - Removing the product arm also removes `pick=product` from validity keys. That is harmless, because directories written with it would simply not be adopted.

### A11. `OSPREY_TRAIN_PICK_RUN=0`: cross-run maximum training row

- **How set:** environment variable (OspreyEnvironment.cs ~ "OSPREY_TRAIN_PICK_RUN" block), readonly.
- **Default:** ON (one sampled run).
- **Why kept:** "setting the variable to 0 restores the historical cross-run maximum for A/B work." The doc also says it is "Rust's criterion in pipeline.rs" (PercolatorSampling.cs:197-201).
- **Code:**
  - The `pickRun` branches in Osprey.FDR/PercolatorSampling.cs:225-~260.
  - PercolatorScorer.cs:800-810 (the reservoir dictionaries and the info log).
  - The `trainpick=max` key arm.
  - ~30 lines.
- **Tests:** FdrTest.cs:4551 (reservoir), TaskValidityKeyTest.cs:483-497.
- **Scripts:** Common/OspreyDatasetRun.psm1 only clears it (:917, 929).
- **Blocker:** a Rust cross-impl comparison would need it unless Rust adopts per-run sampling (inferred).

### A12. `OSPREY_MAX_PARALLEL_FILES`: back-compat concurrency cap

- **How set:** environment variable (OspreyEnvironment.cs:55-68).
- **Default:** 0 (no cap).
- **Why kept:** "legacy back-compat cap on concurrent file processing, superseded by the --parallel-files CLI argument."
- **Code:** `FileParallelismResolver.Resolve` envCap branch (Osprey.Core/FileParallelism.cs:123-163) and PerFileScoringTask.cs:1078. ~25 lines.
- **Tests:** FileParallelismResolverTests.cs:29,58; SubsetPipelineTest.cs:406 (comment).
- **Scripts:** `ai/scripts/Osprey/Test-PerfGate.ps1` uses it as the cross-binary control, because the pinned baseline binary predates `--parallel-files`. 14 references in scripts overall.
- **Blocker:** Test-PerfGate's baseline binary. Re-pin the baseline first.

### A13. Retired-name residue

- **`OSPREY_STAGE7_STREAM`:** `Stage7StreamRetiredSet` (OspreyEnvironment.cs:290-307) and the startup error in Program.cs:579-595 (~35 lines). Test: CommandLineErrorTest.cs:51,144-146. The refusal stops a stale A/B script from mis-labelling its results. Remove it once no script sets the variable; none in `ai/scripts/Osprey` does today.
- **`OSPREY_ALLOW_UNBOUNDED_MEMORY`, `OSPREY_PROTEIN_COMPACT_RETRAIN`, `OSPREY_EXIT_AFTER_SCORING`:** no code reads them; they survive only in comments.
  - ai DIAGNOSTICS.md:375-377 and :410 still document `EXIT_AFTER_SCORING` as live.
  - `ALLOW_UNBOUNDED_MEMORY` is silently ignored if set.
- **`transfer-compete` residue:**
  - The method name `Pass2FdrSidecar.ComputePass2TransferCompeteFull` (:1726) actually implements protein-compact; its resx strings share the old name.
  - The `stratumBaseIds == null` branch in StreamingFdr.cs:205, 660-664 is test-only.
  - Script ValidateSets still offer `transfer-compete`.

### A14 / A15. New: `OSPREY_BLOCK_READ_MB` and `OSPREY_BLOCK_READ_GATE` (OFF arms after the flip)

- **How set:** environment variables (OspreyEnvironment.cs:70-84), readonly. Currently 0 / unset.
- After the flip, the parity-only code is:
  - the `FileStream` branch in `BlockReadStream.OpenRead` (Osprey.IO/BlockReadStream.cs:62-70, ~3 lines);
  - the ungated `else` in `ReadFromDisk` (BlockReadStream.cs:287-300, ~4 lines);
  - the `<= 0` early-out in `BlockReadStats.Text` (Osprey.Core/BlockReadStats.cs:59-60).
- Every reader already goes through `BlockReadStream.OpenRead`: 20 sites in ParquetScoreCache.cs and FdrScoresSidecar.cs:351, 827, 942.
- `BlockReadStats` (70 lines) and `BlockReadLog` (Osprey.Tasks/BlockReadLog.cs, 38 lines) are category B.
- **Tests:** none for either switch or for `BlockReadStream`. Because the values are readonly statics, a test cannot A/B them in-process without making them properties (note for the flip).
- **Memory:** none. One block buffer per open stream, ~MB.

### A16. New: `OSPREY_STUB_IDENTITY` (the 0 arm after the flip to 1)

- **How set:** environment variable (OspreyEnvironment.cs:86-93), readonly, values 0/1/2.
- The code is:
  - `LibraryIdentity` (Osprey.Core/LibraryIdentity.cs, 81 lines, O(library) int arrays);
  - the identity overloads `LoadFdrStubsFromParquet(..., LibraryIdentity)` (ParquetScoreCache.cs:1145-1240) and `ReadFdrStubScalars(..., LibraryIdentity)` (:1368-1454);
  - `AllInLibrary` / `VerifyLibraryIdentity` (:1456-1491);
  - `FirstPassFdrTask.StubIdentity` (:208, 4225-4230), `TryStreamFromLibrary` (:4314-4332) and the call at :4281;
  - `FirstPassSurvivorLoader.Identity` (:121, 192).
- **After the flip, the decode-from-file branch is NOT parity-only.** It is the per-row-group fallback whenever the library lacks an id, and the path when a file has no `is_decoy` column. What becomes parity-only:
  - the `== 0` checks;
  - the non-identity overloads, if no caller remains (tests call them: IOTest.cs:2538, 3629, 3690, 4931-5129);
  - mode 2 (`VerifyLibraryIdentity`, ~25 lines). Mode 2 is a proof harness (B), worth keeping until the flip is banked on a cohort.
- **Tests:** none exercise `LibraryIdentity` or modes 1/2 directly (no `LibraryIdentity` reference in Osprey.Test). Worth adding before the flip.

### A17. Old-format back-compat readers

- `FirstPassModelIO.ModelDto.StratumBaseIds` (FirstPassModelIO.cs:98-105) and the `LoadFromAny` fallback (:178-205). ~15 lines. The doc says "Removable at the next format bump." No test feeds a pre-split file.
- The reconciled parquet `osprey.reconciled = "true"` (pre-#4486 row-parallel shape) is still accepted by `ValidateScoresParquetGroup` (ParquetScoreCache.cs:2443-2452), along with the missing-`score_index` positional fallback (:236-258). This is probably reachable only under `OSPREY_VERSION_OVERRIDE` (inferred).
- Calibration JSON:
  - nullable `Windows` and `RtSearchWindowHalfWidth` "for legacy JSON" (CalibrationParams.cs:162, 309);
  - the uniform-residual fallback in `RTCalibration.FromModelParams` (:533).
- Every binary sidecar is exact-version and has no converters (FdrScoresSidecar v7, FdrExperimentSidecar v2, ReconciliationFile v3, LibraryCache/SpectraCache v4, …), so no other legacy readers exist. FdrExperimentSidecar.cs:61 says "(= 1)", which is stale.

### A18. Dead or test-only code found along the way

These are not switches, but they are worth deleting in the same sweep:
- `FdrProjectionSet.Builder` (Osprey.FDR/FdrProjection.cs:390-495, ~100 lines). Its only caller is FdrTest.cs:4101 (verified).
- `FdrStreamingSink` (Osprey.Tasks/FdrProjectionSinks.cs:356-444, ~90 lines) is never constructed. ScoringTaskShared.cs:881-890 still cites it.
- `RunPercolatorFdr(FdrProjectionSet…)` facade (FirstPassFdrTask.cs:2899-2930) has zero callers.
- `PercolatorQValues.ComputeFullPopulationPrecursorFdr` (PercolatorQValues.cs:308-354, ~47 lines) has zero callers.
- The `frozenModel` parameter (PercolatorEngine.cs:86, 125, 502, 517, 611-629; FirstPassFdrTask.cs:2844, 2884) is never passed non-null (inferred).
- The StreamingFdr.cs:250-255 note "DELETE THIS RECOMPUTE ... before the PR merges" is stale. The recompute is now the deliberate `OSPREY_PASS2_VERIFY_WORKER` instrument (B).

---

## Category B: diagnostic / measurement harnesses (keep unless they serve only a removed path)

- `OSPREY_KEEP_FAILED_WRITES`: forensic; FileSaver keeps the temp file on an abandoned write.
- `OSPREY_MAX_SCORING_WINDOWS`: limits Stage-4 windows for profiling and bisection.
- `OSPREY_EXIT_AFTER_CALIBRATION`: exits after Stage 3.
- `OSPREY_LOG_COASSIGN_ALLOC`: allocation attribution in the co-assignment fold.
- `OSPREY_MDIAG_COASSIGN_ONLY`: ModelDiagnostics co-assignment panel only.
- `OSPREY_LIBRARY_LOAD_ONLY`: loads the library and exits.
- `OSPREY_LOG_MEMORY`: post-GC `[MEM]` probes.
- `OSPREY_LOAD_CALIBRATION`: loads a Rust calibration JSON (feature-parity bisection).
- `OSPREY_CROSS_IMPL_FDR_SIDECAR_OUT`, `OSPREY_CROSS_IMPL_RECONCILIATION_OUT`: test-only cross-impl byte-parity hooks.
- `OSPREY_DROP_BETWEEN_TASKS`: DIAGNOSTIC experiment that emulates HPC dataflow in-process. It also relaxes the Publish guard (PipelineContext.cs:332).
- `OSPREY_PICK_DUMP_CANDIDATES`: per-candidate pick TSV for training pick models.
- `OSPREY_PASS2_VERIFY_WORKER`: Stage-7 recompute and assert (~170 lines). regression.ps1:348 turns it on for the gate; also SubsetPipelineTest.
- `OSPREY_STUB_IDENTITY=2`: library vs file agreement proof (see A16).
- `BlockReadStats` / `BlockReadLog`: block-read totals per phase (see A14).
- `OSPREY_DUMP_*` (25), `OSPREY_*_ONLY` (21), `OSPREY_DIAG_*` (5): the Rust-bisection dump family.
  - Declared in Osprey/OspreyFileDiagnostics.cs:81-390, Osprey.FDR/FdrDiagnostics.cs:61-93 and SpectralScorer.cs:403, **not** in OspreyEnvironment.cs.
  - ~3,400 lines in total.
  - Some of these re-create resident pools (A7).
- `-d` / `--diagnostics`: turns on 19 dumps (see A7).
- `--write-pin`: per-file feature TSV for comparison with Rust PIN output (PerFileScoringTask.cs:2833, 3278).
- `OSPREY_PARQUET_WRITE_THREADS` (ParquetScoreCache.cs:881): 1 for golden A/B.
- `OSPREY_VERSION_OVERRIDE` (OspreyVersion.cs:93): pins the version stamp for goldens.

## Category C: genuine settings / experimental levers (keep)

- `--parallel-files`: file concurrency (replaces A12).
- `OSPREY_MZML_DECODE_THREADS`: mzML decode threads, default 8.
- `OSPREY_FDR_MODEL` (svm | gbdt): GBDT is experimental but "has to keep working".
- `OSPREY_GBT_*` hyper-parameters, including `OSPREY_GBT_MAX_ITERATIONS` and `OSPREY_GBT_INNER_FOLDS`. A value <= 1 reverts to in-sample selection, an old arm, but it is a knob.
- `OSPREY_MAX_TRAIN_SIZE`: training subsample cap.
- `OSPREY_SVM_C_TOLERANCE`: C-selection tolerance. 0 restores the pre-#4703 strict maximum, but it is a numeric knob with no code reserved for 0.
- `OSPREY_EXPERIMENT_AGG` (max | mean-best-N), `OSPREY_MEANBEST2_FLOOR_MEAN`, `OSPREY_MEANBEST2_FLOOR_PCT`: experiment-wide aggregation levers.
- `OSPREY_PASS2_QVALUE` (protein-compact | transfer): the mode is C; transfer's resident placement is A4.
- `OSPREY_PICK_LDA_MODEL`: an override pick model JSON.
- `OSPREY_CAL_MEDIANPOLISH`, `OSPREY_CAL_SAMPLE_SIZE`: experimental calibration levers. They add a new arm rather than keep an old one.
- `--fdrbench-pass 1|2|both`: streams on the default path. Its resident emitter is part of A1.
- `OSPREY_ALLOW_UNFIXED_RESIDENT`: listed under A6 because it exists only to admit A1/A2.
