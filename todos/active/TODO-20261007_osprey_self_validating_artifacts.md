# TODO-20261007_osprey_self_validating_artifacts.md

## Branch Information
- **Branch**: `Skyline/work/20261007_osprey_self_validating_artifacts` (`C:\proj\pwiz-validity`, a worktree of
  `C:\proj\pwiz-scanmajor`)
- **Base**: `Skyline/work/20260612_net8_port`, STACKED on `Skyline/work/20261006_osprey_perfilescoring_round3`
  (0b879300ae: carries the FdrScoresSidecar 1 MB write buffer this work touches again)
- **Created**: 2026-10-07
- **Status**: Implemented and committed (4654250f4c, local, not pushed). Gate 649/649 + inspection 0/0,
  `regression-parallel -Dataset All` 48 PASS / 0 FAIL. Next: `/code-review max`, then PR stacked on the perf
  round 3 PR (Brendan's go-ahead). The matching ai/scripts changes are UNCOMMITTED in C:\proj\ai on purpose
  - commit them when this branch merges (see 2026-10-08 entry).
- **Module**: `osprey`
- **PR**: none

## Objective

Replace the `<artifact>.<Task>.osprey.task` validity sidecars (744 files in an 82-run SEA-AD directory: 9 per
run + 6 experiment-wide) with a validity stamp embedded IN each artifact. Every durable artifact already commits
through FileSaver (P8: presence proves completeness) and is write-once (P11), so a key written into the artifact
cannot drift from its content - the separate stamp exists only because the design was written as if neither
held, and it is the source of several defects (below).

## Decisions (Brendan, 2026-10-07)

1. **Embed the key in the artifact wherever there is a slot.** A single self-describing file is worth more than
   a human-readable stamp file beside it; do not keep stamps "for debugging".
2. **A version change always invalidates artifacts.** `OSPREY_VERSION_OVERRIDE` is the deliberate developer
   escape hatch. Users should not need to reason about which format changes survive a version change (Mike
   prefers knowing a code change invalidates the intermediates).
3. Per-file tasks: one predicate per (input file, task). Progressive per-file completion stays for the *PassFDR
   tasks (a 446-file FirstPassFDR once ran 5 h; stopping midway must not lose completed files).

## Defects in the current mechanism (inventory 2026-10-07, file:line on the base)

- `version` is written but never compared (`TaskValiditySidecar.IsValid` reads only validity_key;
  00-pipeline-architecture.md:1004-1012 calls it a gap).
- The driver re-stamps EVERY declared output that exists at task end (`AnalysisPipeline.WriteTaskSidecars`),
  including stale ones this run rejected; `PerFileRescoreTask.cs:2951-2960` works around it. Every per-file
  stamp is written twice, with different `inputs` lists, and nothing reads `inputs`.
- Stamped but never checked: `.1st-pass.stratum.json`, per-file `.calibration.json`, the 2nd-pass sidecar key
  (Stage 6 resume reads its format header). `Pass2FdrSidecar.HasWorkerStamp` checks PRESENCE while its comment
  claims a current key.
- Two notions of "done" per file (the 2026-09-04 446-run defect) is held off by write ordering (P14) plus a test,
  not prevented by construction.
- `out.model-diagnostics.html` is rewritten yet stamped as a declared output.

## Design

**Stamp**: `(task, version, key)` serialized as one string, `osprey-validity/1;task=<T>;version=<V>;key=<K>`
(key last: it contains `;` and `=`). Current iff the artifact exists, the stamp parses, task matches, version ==
`OspreyVersion.Current` (which honours `OSPREY_VERSION_OVERRIDE`), and key matches.

**Where it lives** (one helper per format family, one dispatcher `ArtifactValidity.TryRead(path)`):
| Family | Artifacts | Slot |
|---|---|---|
| Parquet | `.scores.parquet`, `.scores-reconciled.parquet`, `.training.parquet` | footer KV `osprey.validity` (footer-only read) |
| OSPRY binary | `.1st/2nd-pass.fdr_scores.bin`, `.2nd-pass.fdr_decoys.bin`, `.fdr_experiment.bin`, `retained_base_ids.bin` | length-prefixed stamp after the 32-byte header; format version bump each |
| JSON | `.calibration.json`, `.reconciliation.json` (25 MB), `.1st-pass.model.json`, `.1st-pass.stratum.json`, diagnostics json | FIRST property `osprey_validity`, read by a streaming reader that stops after it |
| blib (SQLite) | `<out>.blib` | small table, or one stamp file if a table is unacceptable - decide in phase 5 |
| HTML report | `<out>.model-diagnostics.html` | rewritten report: drop from declared outputs (regenerable), or a leading comment |
| Already self-validating | `.spectra.bin` (source size + mtime), library cache (library hash) | unchanged |

**Predicates**:
- Per-file task, per input file: EVERY per-file output of the task for that file exists and carries a current
  stamp. A kill between two writes leaves one missing or stale, so the file recomputes - "valid together" by
  construction, no write-order discipline needed (retires P14 as a correctness requirement).
- *PassFDR per-file products: each product's own stamp, checked per file as today (progressive resume kept).
- Driver `CanRehydrate`: every declared output current. The driver no longer writes anything; writers stamp at
  write time, so a rejected stale artifact is never re-certified.
- Cross-task "who wrote this" (P10): read the producer task from the artifact's own stamp.

**Dropped**: the `inputs` provenance list (never read), `TaskValiditySidecar`, `PerFileResumeDriver.ClearStale`
(a stale artifact is simply overwritten), `AnalysisPipeline.WriteTaskSidecars`. Old run directories with only
`.osprey.task` stamps read as stale and recompute - acceptable, since a new build is a new version anyway.

## Phases (keep the build green; migrate task by task, delete the old mechanism last)

- [x] 1. Core: stamp type + per-family read/write helpers + dispatcher; unit tests (round-trip, wrong task /
      version / key, truncated, missing slot, JSON early-stop on a large file)
- [x] 2. PerFileScoring: parquet footer + calibration.json; per-file predicate over both
- [x] 3. FirstPassFDR: per-file 1st-pass sidecar, model/stratum json, reconciliation json; experiment sidecar,
      retained base ids, diagnostics json; resume and compaction-gate checks
- [x] 4. PerFileRescoring: reconciled parquet + both 2nd-pass binaries (+ training parquet); per-file predicate
      over all three; `HasWorkerStamp` and TrainingExport read the embedded producer
- [x] 5. SecondPassFDR: experiment sidecar, blib, diagnostics; decide blib / HTML slots
- [x] 6. Remove TaskValiditySidecar, the driver re-stamp, ClearStale; CanRehydrate on embedded stamps
- [x] 7. Tests: TaskValiditySidecar tests -> stamp tests; SubsetPipelineTest cut scenarios (they delete
      `*.osprey.task` to simulate a cut); add version-mismatch and stale-not-recertified cases
- [x] 8. Harness + docs: regression.ps1 (copies 2nd-pass stamps for the HPC leg, ~2115, ~2546);
      ai/scripts (OspreyDatasetRun -LinkFrom stage lists + version detection from stamps, New-OspreyResumeStage,
      Restamp-OspreyVersion.py and Repair-Stages1to4Stamps.ps1 likely retire, Test-Snapshot, Measure-Stage6Rescore,
      Compare-StraightThroughResume-CSharp, CHS runner); docs 00 (P9, P10, P14, HPC "every artifact travels with
      its stamp"), 14 §8, 15, 20, 22, DIVERGENCES
- [x] 9a. Gates: unit + inspection (649/649, 0/0); `regression-parallel.ps1 -Dataset All` 48/0 (33.5 min)
- [ ] 9b. SEA-AD subset resume drill (kill mid-FirstPassFDR and mid-PerFileRescoring, resume, compare) -
      needs the ai/scripts changes, so run it from C:\proj\ai with this branch's build
- [ ] 10. `/code-review max` in C:\proj\pwiz-validity, then PR (base: perf round 3 branch until it merges)
- [ ] 11. Commit the ai/scripts changes when this branch merges (they assume embedded stamps)
- [ ] Follow-ups (separate work): per-file copies of the experiment-wide stratum.json / model.json
      (82 x 9.6 MB); `OspreyTask.Inputs()` overrides now unused; the early ReconciledPaths decision in
      PerFileRescoreTask (RescoredPoolPlan) no longer required; FirstPassFdrTask.MoveHarnessProductAside
      was forced by the deleted driver re-stamp; stale `IsTaskAlreadyDone` and `--input-scores` mentions

## Progress Log

### 2026-10-07
- Inventory of the current mechanism (Explore agent) and design agreed with Brendan (decisions above).
- Branch created stacked on the perf round 3 branch, which is in PR prep (Stellar + Astral regressions PASSED).
- Implemented phases 1-7 (uncommitted in C:\proj\pwiz-validity):
  - Core: `ArtifactStamp` (Osprey.Core; parse/format, IsCurrent with version check, JSON-head and
    HTML-comment readers) and `BinarySidecarStamp` (header [24..28] length + trailer; shared checked
    length math replacing four copies). `ArtifactValidity.ReadStamp/IsCurrent` (Osprey.IO) dispatches
    by file ending. `BlibWriter.AddStamp/ReadStamp` (OspreyMetadata row). `ParquetScoreCache.ReadStamp/WithStamp`.
  - Formats bumped: fdr_scores v8, fdr_decoys v2, fdr_experiment v3 (its doc said v1/36-byte; fixed),
    retained_base_ids v2. Every writer takes a REQUIRED stamp; `OspreyTask.OutputStamp(ctx[, output])`.
  - PerFileScoring: one per-file predicate over calibration.json + scores.parquet (`IsFileCurrent`).
    PerFileRescoring: `Pass2ArtifactsCurrent` = both 2nd-pass binaries current (was format-only).
    FirstPassFDR declares retained_base_ids. HTML report carries the rendered product's stamp.
  - Deleted: TaskValiditySidecar, AnalysisPipeline.WriteTaskSidecars, PerFileResumeDriver.Stamp/ClearStale,
    OspreyTaskNames.EXT_TASK_FILE/TaskFilePattern (user messages now say delete `*.1st-pass.*`),
    3 resource strings. HasWorkerStamp reads the embedded producer (+ version).
  - Tests: TaskValiditySidecar tests -> `TestArtifactStampEmbedding` (all families, garbage, truncation,
    version); PerFileResumeDriverTest rewritten; comparisons treat the stamp as provenance (BlibComparer
    and BlibGolden.ps1 skip `osprey.validity`; export reproducibility hashes with the stamp blanked -
    the export's run key names input mtimes, so identical content in two dirs has different stamps).
  - Harness: FdrSidecars.ps1 versions + stamp-aware lengths; `Test-ProducedBy` (RegressionData.ps1)
    replaces the stamp-file glob for "worker output shipped"; Invoke-ResumeInvalidation deletes
    FirstPassFDR's `*.1st-pass.*` + `*.reconciliation.json` + output.blib instead of stamps.
- Noted for later: `.1st-pass.stratum.json` (9.6 MB) and `.1st-pass.model.json` are written once PER
  FILE with identical bytes (82 x 9.6 MB = 790 MB at SEA-AD) - experiment-wide products stored per file.

### 2026-10-08
- Committed 4654250f4c (local). Full regression 48 PASS / 0 FAIL; unit 649/649; inspection 0/0.
- Docs updated by delegated agent (00, 01, 11, 13, 14 section 8 rewritten, 15, 20, 22, DIVERGENCES, README);
  stale code comments cleaned (comments only). Dead `OspreyTask.OutputInputs` + `TrainingExportWriter.RunInputs`
  removed; 3 unused resource strings removed; user messages now say delete `*.1st-pass.*`.
- ai/scripts changes (UNCOMMITTED in C:\proj\ai, deliberately): OspreyDatasetRun.psm1 -LinkFrom lists drop
  stamp files and version detection reads the embedded calibration.json stamp with a legacy fallback;
  New-OspreyResumeStage / Test-Snapshot / Measure-Stage6Rescore / Compare-StraightThroughResume-CSharp /
  CHS updated; Restamp-OspreyVersion.py and Repair-Stages1to4Stamps.ps1 marked legacy-only. Also the
  `-ProfileTo` runner switch (OspreyDatasetRun.psm1 + Run-SeaAd.ps1). Holding them because master/port
  builds still rely on linked .osprey.task files.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261007_osprey_self_validating_artifacts.md` before starting work.
