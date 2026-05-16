# TODO-20260516_ospreysharp_wsl_parity.md -- WSL cross-platform parity gate

> **Testing-only.** This TODO instructs the next session to validate
> OspreySharp's `net8.0` build on Linux (via Windows Subsystem for
> Linux) and prove byte-equal output to the Windows reference run
> on the same input. No OspreySharp source code changes are in
> scope; only the test scripts may be adjusted (and only where they
> contain unavoidable Windows-isms). Success criterion: the Stellar
> reverse-decoy snapshot baseline captured on Windows compares
> byte-for-byte against an OspreySharp run under WSL on the same
> mzML + library inputs.

## Branch Information

- **Branch**: `Skyline/work/20260516_ospreysharp_wsl_parity`
  *(local branch created from `master` at `3113544855`, not yet
  pushed; push when a commit lands, or never push if pure
  verification completes with zero commits)*
- **Base**: `master` (`3113544855` -- post-#4217 `--start-page` flag
  which landed after #4215; the WSL gate is dataset-driven and not
  affected by #4217)
- **Created**: 2026-05-16
- **Status**: Not Started (branch ready)
- **GitHub Issue**: (none)
- **PR**: (open only if script adjustments land; pure
  verification may complete with zero commits and a memo on the
  parent NextFlow TODO instead)

## Why this matters now

A lab member is set to start NextFlow testing next week, which
means the `net8.0` OspreySharp build will run on Linux containers
inside an HPC scheduler. Before that handoff, we want
**direct evidence**, not just compile-success, that Linux-built
OspreySharp produces the same output as the Windows reference. WSL
is the cheapest way to get that signal from a Windows dev machine
without provisioning a separate Linux host.

The downstream NextFlow / packaging work tracked at
[`../backlog/brendanx67/TODO-ospreysharp_nextflow_linux_support.md`](../backlog/brendanx67/TODO-ospreysharp_nextflow_linux_support.md)
assumes this gate is green. Run this first.

## Cross-references

- Predecessor (just merged): PR
  [#4215](https://github.com/ProteoWizard/pwiz/pull/4215) /
  `bb1992e248`. Adds the library-decoy CLI flags + harness.
  This TODO uses the test harness #4215 extended.
- Sibling sprint:
  [`TODO-20260516_osprey_libdecoy_e2e_and_fdrbench.md`](TODO-20260516_osprey_libdecoy_e2e_and_fdrbench.md)
  -- the library-decoy E2E gate + `--fdrbench` port. **Independent**
  of this one; can run in parallel. Functional changes belong
  there, not here.
- Downstream:
  [`../backlog/brendanx67/TODO-ospreysharp_nextflow_linux_support.md`](../backlog/brendanx67/TODO-ospreysharp_nextflow_linux_support.md)
  -- the NextFlow / packaging follow-up that becomes safe to start
  once this gate is green.

## Success criterion

Single hard gate:

> Stellar 3-file Test-Snapshot comparison passes byte-equal at
> every stage (`stage1to4 -> stage5 -> stage6 -> stage7 -> blib`)
> when the C# binary that produced the working-directory artifacts
> was built and run under WSL Linux, comparing against the existing
> Stellar same-impl snapshot captured on Windows at v26.6.0
> (`D:\test\osprey-runs\stellar\_snapshots\main\`, captured at
> commit `bb1992e248`).

Stretch (only if the hard gate passes cleanly):

- Astral 3-file same-impl snapshot also PASS under WSL.
- Cross-impl Stellar `Test-Regression.ps1` with both Rust and C#
  sides running under WSL Linux. Requires building Rust osprey
  under WSL too. Defer if it grows; the hard gate above is enough
  for NextFlow handoff.

## Approach: pwsh-on-Linux first, bash translation only if needed

The existing test harness scripts (`Build-OspreySharp.ps1`,
`Test-Snapshot.ps1`, `Test-Regression.ps1`, `Run-Osprey.ps1`,
`Dataset-Config.ps1`) are PowerShell 7 (`pwsh`). PowerShell 7 is
**cross-platform** -- it runs natively on Linux. The two known
Windows-isms in the build script are:

1. `Build-OspreySharp.ps1` invokes `msbuild.exe` from the Visual
   Studio install path. On Linux, this needs to be `dotnet build
   OspreySharp.sln` instead.
2. `vstest.console.exe` is Windows-only. The cross-platform
   equivalent is `dotnet test path/to/Test.csproj`. The Jamfile
   already documents both invocations.

Beyond those, the scripts mostly handle path strings and
filesystem layout, which `pwsh` handles uniformly on either OS.
**The first hour of this sprint should be spent trying the
existing scripts under WSL with minimal modification**; only fall
back to a full bash translation if the build script branches turn
out to be too tangled.

### Path-mapping convention

WSL exposes Windows drives at `/mnt/<letter>/...` by default.
Existing test data at `D:\test\osprey-runs\stellar\` is reachable
from WSL as `/mnt/d/test/osprey-runs/stellar/`. Filesystem
performance through `/mnt/` is slower than the WSL-native
filesystem for many small files; for stable parity testing it is
fine, but if iteration speed becomes a problem, copy the dataset
into `~/osprey-test/` (WSL-native) and set
`$env:OSPREY_TEST_BASE_DIR` accordingly.

The harness already supports an env-var override (set by
`Get-DatasetConfig`). No code change needed to relocate test
data.

## Steps

### Phase 0 -- WSL host setup (one-time)

1. From an elevated PowerShell on Windows:
   ```
   wsl --install -d Ubuntu-22.04
   ```
   (Or use an existing distro; Ubuntu is the safest default.
   WSL2 is the recent-versions Windows default.)
2. Inside the WSL distro:
   ```
   sudo apt-get update
   sudo apt-get install -y wget apt-transport-https software-properties-common
   wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/ms.deb
   sudo dpkg -i /tmp/ms.deb && sudo apt-get update
   sudo apt-get install -y dotnet-sdk-8.0 powershell
   ```
3. Verify:
   ```
   dotnet --info        # should report SDK 8.0.x, RID linux-x64
   pwsh -c '$PSVersionTable.PSVersion'   # 7.x
   ```
4. Confirm the patched `ParquetNet.dll` deploys to the Linux
   build output (it's swapped in by `Directory.Build.targets`'s
   `AfterTargets="Build"`, which works under `dotnet build` on
   Linux; verify after Phase 1).

### Phase 1 -- Build OspreySharp under WSL

From the WSL shell, with `cd /mnt/c/proj/pwiz/pwiz_tools/OspreySharp`:

1. Try the existing build script first:
   ```
   pwsh -File /mnt/c/proj/ai/scripts/OspreySharp/Build-OspreySharp.ps1 \
     -TargetFramework net8.0 -RunTests
   ```
   The `msbuild.exe`-on-Windows branch in `Build-OspreySharp.ps1`
   (around line 153) will fail under Linux. **If that fails**,
   add a Linux branch that calls
   `dotnet build OspreySharp.sln -c Release -f net8.0 -p:Platform=AnyCPU`
   (note: `AnyCPU`, not `x64`, on Linux because the SDK-style
   csprojs already declare both per
   `Directory.Build.props`; verify by reading that file before
   modifying the build script).
2. Confirm:
   - All 346 unit tests pass under WSL (same count as Windows
     post-#4215).
   - `OspreySharp.exe` lands at
     `OspreySharp/bin/AnyCPU/Release/net8.0/OspreySharp` (the
     suffix-less form on Linux; check) or
     `bin/x64/Release/net8.0/OspreySharp` if the build still uses
     the x64 layout.
   - `runtimes/linux-x64/native/` contains `libnironcompress.so`
     and `SQLite.Interop.dll` (well, the Linux equivalent for
     SQLite). The Linux-side SQLite native is named
     differently; verify the SQLite library opens cleanly during
     test execution.
3. **If any test fails**, that is a real cross-platform bug --
   capture the failing test name and `dotnet test --logger`
   output and add a finding to the progress log below before
   continuing. Don't paper over it.

### Phase 2 -- Run the Stellar same-impl snapshot under WSL

1. Set `$env:OSPREY_TEST_BASE_DIR=/mnt/d/test/osprey-runs`
   (so the scripts find the existing test data without
   copying).
2. Run:
   ```
   pwsh -File /mnt/c/proj/ai/scripts/OspreySharp/Test-Snapshot.ps1 \
     -Dataset Stellar -Files All
   ```
   (compare mode -- no `-CreateSnapshot`. We are comparing
   against the existing Windows-captured snapshot.)
3. Expected result: PASS at every stage. The C# binary running
   under Linux should produce byte-equal output to the Windows
   reference because both are the same managed assemblies on the
   same .NET 8 runtime, just different OS hosts.

**Likely failure modes** (debug in this order before assuming a
real Linux bug):

- **Path-string divergence**: `Path.DirectorySeparatorChar` differs
  ('\\' on Windows, '/' on Linux). If a path string ends up in any
  hashed output (parquet metadata, blib metadata, scores), the
  hash will diverge. The harness already excludes
  full-path-strings from the search hash via
  `LibraryIdentityHash`, but verify there's no per-file path
  leaking into the parquet metadata. Likely safe; pin in tests
  if found.
- **Line-ending divergence**: TSV writers using
  `Environment.NewLine` produce CRLF on Windows, LF on Linux.
  Check the blib and TSV outputs. If found, switch the writers to
  emit `"\n"` literal and pin in tests.
- **Locale / culture default**: floating-point formatting can
  differ if a writer forgot `CultureInfo.InvariantCulture`. The
  search hash already uses invariant culture; sweep the blib
  writer and TSV writers for any missing `InvariantCulture`
  argument.
- **Patched Parquet.Net not deployed under Linux**:
  `Directory.Build.targets` swaps `ParquetNet.dll` in after the
  managed build. Verify the post-build copy step actually fires
  under `dotnet build` on Linux. If it doesn't, parquet read/write
  byte-divergence is the immediate consequence.

### Phase 3 -- Report

1. If the Stellar same-impl gate PASSes:
   - Note the result in this TODO's progress log with the WSL
     distro / kernel / dotnet versions.
   - Re-link the NextFlow backlog TODO confirming the gate is
     green and the lab member can proceed.
   - Stretch: run Astral same-impl. If that also PASSes, declare
     same-impl cross-platform parity validated.
2. If it FAILS:
   - Capture the failing stage's per-stage diagnostic output to
     `ai/.tmp/wsl-parity-fail-<stage>.log`.
   - Run the same Test-Snapshot from Windows on a fresh check-out
     to confirm the baseline still passes Windows-on-Windows
     (rules out baseline corruption).
   - Diff the per-stage artifacts (stage5 dumps, stage6 reconciled
     parquet, stage7 protein TSV, blib) to identify the first
     point of divergence. Update this TODO with the bisection
     result and stop -- the fix belongs in a separate functional
     TODO, not this one.

## Stretch: cross-impl under WSL

Only after Phase 2 PASSes and you have time:

1. Build Rust osprey under WSL:
   ```
   cd /mnt/c/proj/osprey   # or copy to ~/osprey-rust
   cargo build --release
   ```
   (May need to install build-essential, libssl-dev, pkg-config.)
2. Update `Test-Regression.ps1`'s Rust-binary path resolution to
   pick the Linux build under WSL (currently hardcoded to
   `osprey\target\release\osprey.exe`; check).
3. Run:
   ```
   pwsh -File /mnt/c/proj/ai/scripts/OspreySharp/Test-Regression.ps1 \
     -Dataset Stellar -Files All -Force
   ```
4. Expected: PASS at every stage, same as the Windows-side gate.
   Any divergence is a Linux-host bug in either implementation.

## Out of scope

- **OspreySharp source code changes.** This TODO is verification.
  Findings that require code changes get rolled into the
  appropriate functional TODO (the sibling
  `TODO-20260516_osprey_libdecoy_e2e_and_fdrbench.md`, or a new
  TODO if it's strictly a cross-platform fix).
- **Packaging / `dotnet publish` infrastructure.** Tracked at
  `../backlog/brendanx67/TODO-ospreysharp_nextflow_linux_support.md`.
- **Library-decoy / `--fdrbench` cross-platform validation.** The
  sibling TODO handles the library-decoy gate on Windows first;
  once that's landed, validating it under WSL is a one-line
  follow-up here, not a separate sprint.
- **macOS or non-WSL Linux validation.** WSL is the lab's nearest
  target. Further OS coverage waits for an actual user demand.

## Progress log

### 2026-05-16 -- Sprint planned

- TODO created in response to the lab-member NextFlow-testing
  handoff approaching next week.
- Approach decision: try pwsh-on-Linux on the existing scripts
  first; bash translation only if `Build-OspreySharp.ps1`'s
  `msbuild`-via-Visual-Studio branch is too tangled to extend.
- Hard gate: Stellar 3-file same-impl snapshot PASS comparing a
  WSL-built C# run against the Windows-captured baseline at
  `bb1992e248`.
- pwiz already on `Skyline/work/20260516_ospreysharp_wsl_parity`
  (created from master at `3113544855`, not pushed); old merged
  `20260515_osprey_catchup_followup` branch deleted locally. ai
  on master, clean.
- **Next session handoff**: For detailed startup protocol, read
  `ai/.tmp/handoff-20260516_ospreysharp_wsl_parity.md` before
  starting work. The handoff has the repo-state confirmation
  step, skill load list, the Windows baseline freshness check,
  and the out-of-scope reminders.
