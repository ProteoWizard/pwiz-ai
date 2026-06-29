# TODO: Osprey NextFlow / Linux deployment

## Why

A lab member plans to start NextFlow testing on Osprey next week
(post-2026-05-18). NextFlow workflows almost always run under Linux
containers, which means the `net8.0` build needs to be a first-class
deployment target -- not just "happens to compile." Osprey's
task-architecture rearchitecture (vs. Rust osprey's 7000-line monolithic
pipeline) is what makes it the right target for distributed scheduling
in the first place; this work delivers the packaging and platform
audit that lets the architecture pay off in practice.

This is a new-feature track, *not* part of the Mike-catch-up arc.
Status: planning only -- no commits yet.

## What ships today (baseline)

Release output today (per audit on 2026-05-15):

- Framework-dependent .NET 8 (or net472) drop, ~40-50 files, ~50 MB
- `Osprey.exe` + 9 Osprey managed DLLs + ~14 third-party
  managed DLLs (Parquet.Net patched overlay, Apache.Arrow, MathNet,
  Microsoft.ML.DataView, Newtonsoft.Json, DotNetZip,
  System.Data.SQLite, Snappier, ZstdSharp, JetBrains profiler shim)
- `runtimes/{linux-x64, linux-arm64, osx-x64, osx-arm64, win-x64,
  win-x86}/native/` -- native interop deps (SQLite, libnironcompress)
- `Osprey.runtimeconfig.json` -- runtime version + server GC
- Patched `Parquet.dll` overlay swapped in by
  `pwiz_tools/Osprey/Directory.Build.targets` to fix a Thrift
  struct-skip bug reading parquet-rs >=58 files

**Not in place yet**:

- No `dotnet publish` profile; no single-file or AOT output
- No Linux smoke-test in CI
- No path-handling / line-ending audit for `Path.DirectorySeparatorChar`
  hardcoded `'\\'` vs `Path.Combine`
- No documented runtime install pre-req for end users

## Plan

### Phase A -- Linux packaging (~1 session)

1. Add `ai/scripts/Osprey/Publish-Osprey.ps1` (and `.sh`
   counterpart) that wraps `dotnet publish -c Release -r <RID>
   --self-contained false` for the supported RIDs (linux-x64 first,
   then osx-arm64, then win-x64), and emits a `.tar.gz` at
   `pwiz_tools/Osprey/dist/Osprey-<version>-<rid>.tar.gz`.
2. Emit a `RUNNING.md` next to the tarball that documents the dotnet
   8 runtime install requirement and the smoke-test command.
3. TeamCity build config that runs Publish-Osprey on every
   pwiz/master push and archives the tarballs as build artifacts.

### Phase B -- Path / line-ending audit (~1 session)

1. Grep-audit pass for `'\\'` literal vs `Path.Combine`,
   `Environment.NewLine` usage in TSV/CSV writers, hardcoded
   `Path.GetTempPath()` semantics (Windows: `%TEMP%`; Linux:
   `/tmp` -- the path is the same shape but tooling assumptions
   differ).
2. Pin-test DiannTsvLoader on a TSV with `\n`-only line endings
   (DIA-NN on Linux emits these natively); currently we have no
   regression for that case.
3. Add a path-platform test that exercises `OspreyConfig` /
   `LibrarySource` / `FileSaver` round-trips with both `/`-rooted
   and `C:\`-rooted paths and verifies cross-impl hash stability
   (already tested for `DecoyPairingManifestPath` -- audit the
   rest).

### Phase C -- Linux smoke test in CI (~1 session)

1. Smallest viable: a Linux job that runs `dotnet
   Osprey.Test.dll --filter ...` on the existing test suite,
   confirms all 340+ tests pass.
2. Bigger: spin up the 3-file Stellar dataset on a Linux runner,
   produce a `.blib`, byte-compare against the Windows reference
   `.blib`. Requires staging the Stellar mzML data to a Linux-
   accessible location -- ask Mike whether `/share/labdata/...` is
   reachable from a TeamCity Linux agent.
3. Add this as a status check on every PR touching
   `pwiz_tools/Osprey/**`.

### Phase D -- Self-contained / single-file builds (~0.5 session)

1. Add a `--SelfContained` switch to `Publish-Osprey.ps1` that
   emits a self-contained tarball (doubles the size to ~120 MB but
   removes the dotnet-runtime-install prereq).
2. Try `<PublishSingleFile>true</PublishSingleFile>` for the
   self-contained build to see if it works with the native-interop
   `runtimes/` payload. If not, document why and ship the multi-file
   self-contained build as the NextFlow recommended packaging.

## Open questions

- Should we publish Osprey tarballs to GitHub Releases on tags?
  Or stay TeamCity-internal for now?
- Does the NextFlow user have a specific RID requirement
  (linux-x64 vs linux-arm64)? Linux-x64 is the default first target.
- The patched `Parquet.dll` overlay is currently applied via an
  `AfterTargets="Build"` step. Does `dotnet publish` pick up the
  patched file or revert to the NuGet-resolved one? Worth a quick
  diff on the published tarball before declaring Phase A done.
- The Osprey DIAGNOSTIC env vars and the `_test_*` workdir
  conventions assume forward-slash-compatible paths; verify on
  Linux before the smoke test.

## Dependencies / blockers

- No external blockers -- starts whenever a developer picks it up.
- Coordinate scheduling with the lab member doing NextFlow testing
  so packaging arrives before they hit the wall on it.

## Related

- `pwiz_tools/Osprey/Osprey-workflow.html` -- the conceptual
  architecture diagram that makes NextFlow a natural target.
- `ai/scripts/Osprey/Build-Osprey.ps1` -- the existing
  build script that this work builds on.
- `pwiz_tools/Osprey/Directory.Build.targets` -- the patched-
  Parquet overlay that Publish-Osprey.ps1 must preserve.
