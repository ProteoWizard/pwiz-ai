# TODO-20261103_osprey_linux_path_audit.md

## Branch Information
- **Branch**: `Skyline/work/20261103_osprey_linux_path_audit`
- **Base**: `master` (4ec653c0d4)
- **Created**: 2026-11-03
- **Status**: In Progress (night-session agent F; worktree `C:\proj\wt-carafe`)
- **GitHub Issue**: [#4361](https://github.com/ProteoWizard/pwiz/issues/4361) (Phase B only; the issue stays open)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

#4361 Phase B: audit `pwiz_tools/Osprey` for path and line-ending assumptions that break or
drift on Linux, fix the real defects, and pin the behavior with tests:
- a pin test that `DiannTsvLoader` reads LF-only input to exactly what it reads from CRLF input;
- a path-platform test that the artifact / library-source / output-path derivations round-trip
  `/`-rooted and `C:\`-rooted paths.

Out of scope (decision 6, no TeamCity changes): the Linux end-to-end byte-compare as a CI status
check and the server-side activation of the Osprey Linux .NET config. Both stay open on #4361.

## Tasks

- [x] Audit (results below)
- [x] Fix: platform path comparison (`PathComparison` in Osprey.Core) at the case-insensitive sites
- [x] Fix: `<stem>.calibration.json` written with LF on every platform
- [x] Pin test: DIA-NN TSV LF vs CRLF (in `TestLibraryLoadsIdenticallyFromTsvAndBlib`)
- [x] Path-platform test (`ArtifactPathsTest.TestPathDerivationsAcrossPathStyles`)
- [x] Build-Osprey -RunTests -RunInspection: 651/651, 0 warnings (`ai/.tmp/sessions/20261103-agentF/build3.log`)
- [x] regression.ps1 -Dataset Stellar: PASSED, mode1 vs golden PASS (`ai/.tmp/sessions/20261103-agentF/regression-stellar.log`)
- [x] Run the new tests on Linux (WSL, .NET 10 SDK at /root/.dotnet) if the tree builds there -
  NOT DONE. A `git archive` of `pwiz`, `pwiz_tools/{Osprey,CarafeSharp,Shared}`, `build`,
  `libraries`, `vendor-archives` and the root props extracted to WSL `~/p4361` failed in
  `build/VendorPinsGenerator` (exit 1), and diagnosing it means running `dotnet` directly, which
  `Deny-DirectBuildTest.ps1` blocks. Stopped there rather than work around the hook. The Linux
  half of the new tests is written so it runs as-is on the Osprey Linux .NET config once that is
  activated. Session scripts: `ai/.tmp/sessions/20261103-agentF/wsl-setup.sh`.
- [x] /code-review medium, triage (below)
- [ ] PR, status comment on #4361

## Audit (base 4ec653c0d4)

Literal `'\\'` / `"\\"` in path construction: none in production code. Every artifact path is
`Path.Combine` + `Path.GetFileNameWithoutExtension`; `Program.CanonicalizeOutputPaths` and
`ArtifactPaths.InputDir` already make output and input directories absolute with the platform
separator (an earlier fix for `D:/runs/x\file`). Remaining backslash literals are in tests only
(Windows-shaped strings that are never opened, or pinned outputs of pure string derivation).

Readers: `DiannTsvLoader`, the input list and every JSON reader go through `ReadLine` /
`ReadAllLines` / Newtonsoft, all of which accept LF, CRLF and CR. No reader splits on `'\n'`.

Writers (line endings):
- Product artifacts compared byte-wise or cross-impl already write LF on every platform:
  `OspreyReportWriter`, `FdrBenchInputWriter`, `PickCandidateDump`, `PercolatorDiagnosticsDump`,
  the reconciliation / first-pass model / Stage 6 consensus JSON (`RoundtripDoubleConverter.NormalizeJson`).
- `CalibrationIO.SaveCalibration` (`<stem>.calibration.json`, a per-run product read by
  `OSPREY_LOAD_CALIBRATION` and the Rust bisection tooling) used Newtonsoft `Formatting.Indented`
  unnormalized: CRLF on Windows, LF on Linux. The one per-run product whose bytes depended on the
  platform. FIX: normalize to LF (no trailing newline added, so Linux output is unchanged).
- Developer diagnostic dumps (`FdrDiagnostics`, about half of `OspreyFileDiagnostics`,
  `PeakDataExtractor` search XIC append, `SpectralScorer` `cs_xcorr_diag.txt`) use the platform
  `NewLine`. On Linux that is LF, which is what Rust writes, so no Linux defect; on Windows they
  are CRLF. NOT changed: diagnostics only, the Compare tooling reads them line-wise, and a sweep of
  ~20 writers is churn with no reader that needs it.
- Log (`CommandStatusWriter`) and console text: platform line endings by design.

Case sensitivity (Linux file systems are case-sensitive):
- `Program.IsSamePath` already switches to Ordinal on Linux. Not shared, so other sites did not:
  - `FdrScoresSidecar.WrittenThisRun` (OrdinalIgnoreCase): on Linux, runs `A.mzML` and `a.mzML`
    write distinct sidecars, and the write-once guard would throw "written twice". Linux defect.
  - `ParquetScoreCache._chargesChecked` (OrdinalIgnoreCase): on Linux the second of two
    case-variant parquets would skip its charge check. Linux defect.
  - `ScoringTaskShared.FirstPassProductStampProblem` sibling self-match (OrdinalIgnoreCase).
  - `FirstPassFdrTask` / `SecondPassFdrTask` output-vs-own-product exclusions (OrdinalIgnoreCase;
    both sides come from one config, so no live defect - converted for consistency).
  FIX: `PathComparison` in Osprey.Core (Comparison / Comparer / IsSamePath) used at all of them,
  and `Program.IsSamePath` folded into it.
- NOT changed (first draft changed it, reverted after review): `Program.DuplicateInputStemError`
  stays Ordinal. On Windows `Run1.mzML` and `run1.mzML` collide on disk ONLY when they share an
  output directory (`--output-dir`/`--work-dir`, or one input folder); with artifacts beside each
  input they are fine, and the per-run maps are Ordinal. A platform comparer would refuse the
  legitimate two-folder case. A precise check would compare (resolved artifact dir, stem) under
  `PathComparison` - left for Brendan (see Decisions).
- Left as is: `ArtifactPaths._writable` (Ordinal on purpose, documented), `DiagnosticFileLock`
  (Ordinal default; diagnostics only).

`Path.GetTempPath`: tests only, always through `Path.Combine`; production never uses it.

Environment variables: names compared per platform already (`OspreyEnvironment.VariableNameComparison`).
Path-valued variables (`OSPREY_LOAD_CALIBRATION`, `OSPREY_PICK_LDA_MODEL`,
`OSPREY_CROSS_IMPL_*_OUT`) are passed straight to `File` APIs - no splitting, no separator
assumptions. Diagnostic dumps are written to cwd-relative names, portable. No `_test_*` workdir
convention exists in the C# tree (it was a Rust-side convention).

Hashes: `SearchIdentity.FileIdentityHash` hashes file name + size + mtime, never the directory,
so a native path identifies identically on Windows and Linux. The reconciliation hash uses stems.

## Decisions Brendan might revisit

- Windows case-only stem collisions in a shared output directory (`Run1`/`run1` with
  `--output-dir`) are still not refused. Fix would be a check on (resolved artifact dir, stem)
  compared with `PathComparison`; not done because it is a Windows behavior change outside the
  Linux audit and the plain platform-comparer version over-refuses (review finding 1).
- Diagnostic dumps keep platform line endings (see above).
- `<stem>.calibration.json` is LF-normalized but gets no trailing newline (unlike the files that
  go through `RoundtripDoubleConverter.NormalizeJson`), so Linux bytes stay exactly as before.

## Code review (/code-review medium, 6 findings)

1. DuplicateInputStemError over-refuses two-folder case-variant stems on Windows - FIXED by
   reverting that change (see above).
2. FirstPass/SecondPassFdrTask still OrdinalIgnoreCase - FIXED (PathComparison.Comparison).
3. Test used `!IsLinux` for "backslash separates" - wrong on macOS - FIXED (`IsWindows`).
4. Calibration JSON lacks NormalizeJson's trailing LF - DROPPED: adding it changes Linux bytes,
   and the point of the change is platform-identical output, not Rust byte-parity of a file no
   comparator byte-compares; moving NormalizeJson to Core is churn for one caller.
5. Identity assertions depended on files not existing (relative `lib.tsv`) - FIXED (GUID dirs).
6. `_chargesChecked` comment overclaimed (keys not GetFullPath-normalized) - FIXED (comment);
   normalizing keys is a perf nicety, not a defect.

## Progress Log

### 2026-11-03 (agent F, night session)
- Read the brief, #4361 and its 2026-09-18 status; audited (above).
- Implemented fixes and tests; build2 651/651; /code-review medium (6 findings, triaged below);
  build3 651/651 + 0 inspection warnings; Stellar regression PASSED.
- Committed 720873cf19 on the branch; PR and #4361 status comment next.
