# TODO-20260125_dottrace_cli_integration.md

## Branch Information
- **Branch**: (none - ai/ repo only)
- **Base**: `master`
- **Created**: 2026-01-25
- **Status**: Complete
- **GitHub Issue**: (none)
- **PR**: (none - ai/ repo changes only)

## Objective

Integrate dotTrace CLI into Run-Tests.ps1 for automated performance profiling with text output.
Unlike dotMemory, dotTrace has Reporter.exe that can export XML reports - enabling full automation.

## Background

From our dotMemory investigation, we discovered:
- dotTrace GUI installation includes `Reporter.exe` at `%LOCALAPPDATA%\JetBrains\Installations\dotTrace253\`
- Reporter.exe can: generate XML reports from snapshots, compare two snapshots
- This enables automated performance regression detection

Test case: TODO-20260102_FilesViewPerfRegression.md
- TestImportHundredsOfReplicates regressed from 136s to 3568s
- Manual profiling identified FilesTree.MergeNodes as bottleneck
- With dotTrace automation, this could have been detected and diagnosed faster

## Tasks

### Research
- [x] Document Reporter.exe capabilities and XML output format
- [x] Understand dotTrace CLI snapshot format (.dtp files)
- [x] Determine if pattern file is needed for useful reports

### Implementation
- [x] Add `-PerformanceProfile` switch to Run-Tests.ps1
- [x] Add dotTrace CLI discovery (uses .NET global tool)
- [x] Add Reporter.exe discovery (searches JetBrains GUI installation)
- [x] Build dotTrace CLI command for profiling
- [x] Call Reporter.exe to generate XML report
- [x] Parse XML to extract hot spots / timing data
- [x] Display top 10 hot spots automatically

### Verification
- [x] Test with AaantivirusTestExclusion - basic workflow works
- [x] Verify XML output shows method timing data with call stacks
- [x] Synthetic end-to-end validation (completed 2026-02-18)

## Synthetic Validation Results (2026-02-18)

Used `MeanTest` from `StatisticsTest.cs` with a `Thread.Sleep(2000)` in `Statistics.Mean()`.

### Baseline (no hotspot)
- Test duration: 0.2s
- Top hot spots: test infrastructure only (ProcessEx, Settings, Program.Init)
- `Statistics.Mean` not in top 10

### With artificial hotspot (Thread.Sleep(2000) in Mean())
- Test duration: 4.1s
- `Statistics.Mean` reported as **#1 hot spot at 4006ms** (called twice by MeanTest)
- Clear signal-to-noise ratio - artificial delay dominated the profile

### What was validated
- dotTrace CLI discovery and invocation
- Snapshot capture (.dtp file)
- Reporter.exe XML export with pattern file
- Hot spot parsing and display (top 10 pwiz.* methods by TotalTime)
- Full end-to-end pipeline from `Run-Tests.ps1 -PerformanceProfile`

## Installation Note: dotTrace CLI and .NET 9

dotTrace CLI 2025.3.2 ships with a broken `runtimeconfig.json` that targets `net6.0` with
`rollForward: Major`, but the tool's assemblies are compiled for .NET 8. On machines with
.NET 9 SDK, the tool rolls forward to .NET 9 runtime where `System.Runtime` is version 9.0.0,
not 8.0.0 as the assemblies expect, causing a `FileLoadException`.

**Fix**: Edit both runtimeconfig files in the tool store to pin to .NET 8:
- `~/.dotnet/tools/.store/jetbrains.dottrace.globaltools/<version>/.../dottrace.runtimeconfig.json`
- `~/.dotnet/tools/.store/jetbrains.dottrace.globaltools/<version>/.../dottrace.runtimeconfig.win.json`

Change `tfm` to `net8.0`, `rollForward` to `LatestMinor`, and framework version to `8.0.0`.

This should be documented in the setup guide (`ai/docs/new-machine-setup.md`).

## Reporter.exe Capabilities

From earlier exploration:
```
Reporter.exe report <snapshot.dtp> --pattern=<pattern.xml> --save-to=<result.xml>
Reporter.exe compare <snapshot1.dtp> <snapshot2.dtp> --pattern=<pattern.xml> --save-to=<compare.xml>
```

## Vision

Automated performance regression detection:
1. Run test with `-PerformanceProfile` -> produces .dtp snapshot
2. Reporter.exe exports XML with method timings
3. Parse XML to identify hot spots
4. Compare against baseline to detect regressions
5. Include in nightly test reports

## Files Modified

- `ai/scripts/Skyline/Run-Tests.ps1` - Performance profiling integration
- `ai/docs/new-machine-setup.md` - dotTrace CLI in developer tools section

## Related

- dotMemory integration: PR #3870 (merged)
- FilesView perf regression: TODO-20260102_FilesViewPerfRegression.md
