# TODO-20260920_osprey_filesaver_universal.md - Made "artifact" writes go through FileSaver, "log" writes stream directly

## Branch Information
- **Branch**: `Skyline/work/20260920_osprey_filesaver_universal` (checkout `C:\proj\pwiz-work1`)
- **Base**: `Skyline/work/20260612_net8_port` (the .NET 10 port, PR #4619), synced to its tip as of
  merge commit `412751ae97` (2026-09-22) + a local merge on top for the log/artifact simplification
- **Module**: `osprey`
- **Status**: PR #4694 open (base = port branch); local gates green post-sync; /code-review re-review
  of the log/artifact simplification and TeamCity still pending

## Why

Follow-up to #4690 (docs/00's P8 principle). Brendan: "There is no reason to write any
file in Osprey without using FileSaver. Or if there seems to be an exemption, run that
by me before deciding it should remain." Full-tree audit found ~50 write sites still
opening their final path directly.

## Decisions made with Brendan

1. **`--log-file` stream stays exempt.** Written incrementally for the life of the run
   so it can be live-tailed (`ai/CLAUDE.md` directs sessions to use it this way);
   FileSaver's temp-until-Commit model would hide it until the run ends and leave
   nothing after a crash. Documented in docs/00 and docs/14.
2. **`FdrDiagnostics.CoAssignRowDump`** — its own doc comment said partial rows
   surviving a mid-panel throw was deliberate. Brendan pushed back: that reasoning
   would apply equally to every other TSV bisection dump, and asked whether the real
   distinction was file format (TSV degrades gracefully; JSON/HTML does not) rather
   than a one-off exemption. He proposed a general FileSaver-level opt-in to keep a
   failed write's temp for forensics — new for this codebase, not yet in Skyline.
   Implemented as `OspreyEnvironment.KeepFailedWrites` / `OSPREY_KEEP_FAILED_WRITES`:
   `FileSaver.Dispose()` leaves an uncommitted temp in place instead of deleting it,
   never touching the real path, so presence still proves completeness for every
   ordinary reader. `CoAssignRowDump` itself now commits unconditionally in `Dispose`
   (not via the flag) since its caller's `using` block guarantees `Dispose` runs even
   on a throw, and nothing downstream reads the file back — see its doc comment.

## Scope

- `PerFileScoringTask.WriteFeatureDump` (`cs_features.tsv`) — the case that started this.
- `OspreyFileDiagnostics.cs`: 25 dump methods, incl. 3 long-lived streams
  (`_mpInputsWriter`, `_predictRtWriter`, `_cwtPathWriter` — `FileSaver` opened
  alongside the writer, committed in the existing `CloseXDump`) and one append-
  accumulate dump (`WriteStage6CalibrationDump` — read-existing + fresh-`FileSaver`
  rewrite per call, serialized by a new process-local lock; was unlocked `append:
  true` before, an existing hazard this also closes).
- `FdrDiagnostics.cs`: `CoAssignRowDump` (rows + cutoffs) + 2 more one-shot dumps.
- `PercolatorDiagnosticsDump.cs` (4), `PickCandidateDump.cs` (1).
- `PeakDataExtractor.cs`'s search-XIC dump — same append-accumulate treatment as
  `WriteStage6CalibrationDump`, gated to specific candidate ids so call volume is small.
- `FileSaver.cs` / `OspreyEnvironment.cs`: new `KeepFailedWrites` opt-in.
- `FileSaverTest.cs`: new test for the opt-in.
- docs/00 P8 section and docs/14's call-site table rewritten for the new inventory.

Out of scope, confirmed not artifact writes: `ArtifactPaths.ProbeWritable` (zero-byte,
self-deleting writability check — no content ever persists).

## Gates

- [x] `Build-Osprey.ps1 -SourceRoot C:\proj\pwiz-work1 -Configuration Debug -RunTests -RunInspection` - 593/593 (incl. new `TestFileSaverKeepFailedWrites`), zero warnings
- [x] `regression.ps1 -Dataset Stellar` - PASSED, all modes
- [x] `/code-review max 4694` - 15 findings, 13 fixed in de3db716c9, 2 addressed by documentation (multi-process HPC race; pre-existing NaN/rounding format gap left out of scope)
- [x] Log/artifact simplification (2026-09-22, commit `8684e0ead5`): re-ran `Build-Osprey.ps1 -RunTests
      -RunInspection` - 595/595, zero warnings
- [x] Synced with PR #4619's tip (merge commit `412751ae97` on origin, then a local merge on top):
      re-ran `Build-Osprey.ps1 -RunTests -RunInspection` - 595/595, zero warnings
- [x] `regression.ps1 -Dataset Stellar` re-run post-sync - PASSED, all modes
- [ ] TeamCity Perf/Regression on `pull/4694` with the agent pin (ask first)

**Review round (2026-09-20/21)**: `/code-review max` found 15 issues, mostly real races/leaks the
conversion introduced (two unsynchronized writers of the same search-XIC file; CoAssignRowDump
not surviving its own writer throwing; its filename-collision check racing FileSaver's deferred
real-path existence; Environment.Exit - two dozen call sites - abandoning the three held-open
dumps' FileSaver temps instead of committing; WriteStage6CalibrationDump's O(files^2) re-read).
Fixed: new Osprey.Core.DiagnosticFileLock (shared per-path lock, process-local by design);
CoAssignRowDump's Dispose and NextSequence; a CloseAll registered on AppDomain.ProcessExit;
WriteStage6CalibrationDump restructured to the held-open pattern (4th such stream); the
two-step FileSaver+StreamWriter construction leak in 4 places; missing InvariantCulture in
WriteFeatureDump; docs/00's inaccurate description of which writer commits unconditionally.
Not fixed: true multi-process HPC fan-out sharing one directory (documented limitation - these
dumps are single-session opt-ins); a pre-existing NaN/rounding formatting gap unrelated to
write atomicity (out of scope, worth its own issue). All three gates re-run clean after.

**Not exercised**: none of the `-d`-gated dump paths were run live end-to-end (no
cached mzML on hand for a quick manual smoke test); confidence rests on the uniform
mechanical pattern, `FileSaverTest.cs` coverage of the primitive itself, and three
clean build/test/inspection passes. Pre-existing gap — none of these methods had
direct test coverage before this branch either.

## Progress

- 2026-09-20: full-tree audit (grep for every raw file-write API, classified each);
  two decisions confirmed with Brendan; conversions applied (some by me directly for
  the streaming/append/unconditional-commit cases, the ~30 one-shot dumps delegated
  to two parallel agents); three clean gate runs (one race with a concurrently-running
  regression.ps1 build caught a real but already-fixed inconsistency, re-run clean).
- 2026-09-21/22: Brendan reviewed the diff and pushed back on the FileSaver conversion for
  debugging-only diagnostics - too large and complex for what these files are, and
  `CoAssignRowDump`'s unconditional-`Commit()` override read as fighting FileSaver's
  contract rather than benefiting from it. Landed on a "log" vs "artifact" distinction:
  atomicity matters where a *reader* (downstream code, or a second concurrent writer)
  depends on presence proving completeness; for a debug dump whose only reader is a human
  or a Claude session doing bisection, showing how far processing got before a crash is
  more valuable than all-or-nothing. `CoAssignRowDump`'s rows file and the four
  `OspreyFileDiagnostics` held-open streams (`cs_stage6_mp_inputs.tsv`,
  `cs_stage6_predict_rt.tsv`, `cs_stage6_cwt_path.tsv`, `cs_stage6_calibration.tsv`) fit
  the "log" case and now write directly to their final path, no `FileSaver`, no
  `KeepFailedWrites` dependency. `PeakDataExtractor`'s search-XIC dump stays an artifact
  (two independent call sites write the same file - a concurrent-writer hazard, not a
  partial-progress one). Committed as `8684e0ead5`; net ~30 fewer lines than the prior
  state. docs/00's P8 section and docs/14's table rewritten to describe the split.
- 2026-09-22: found PR #4619 had moved 3 commits past this branch's base (most notably
  #4693, an Osprey task-list refactor touching `PerFileScoringTask.cs` and this branch's
  own docs/00 - GitHub's "Update branch" button never appears for any PR in this repo
  because `allow_update_branch` is off repo-wide, unrelated to which branch is base).
  Merged #4619's tip into the branch (origin now carries merge commit `412751ae97`);
  verified by hand that `WriteFeatureDump` still uses `FileSaver` post-merge and that the
  merged docs/00 P8 section reflects the current log/artifact split, not #4693's
  now-stale wording. Re-ran build/test/inspection clean (595/595) and
  `regression.ps1 -Dataset Stellar` - PASSED, all modes. Pushing now.
