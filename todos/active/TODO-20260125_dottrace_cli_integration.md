# TODO-20260125_dottrace_cli_integration.md

## Branch Information
- **Branch**: `Skyline/work/20260125_dottrace_cli_integration`
- **Base**: `master`
- **Created**: 2026-01-25
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (pending)

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
- [ ] Synthetic end-to-end validation (see Next Steps below)

## Reporter.exe Capabilities

From earlier exploration:
```
Reporter.exe report <snapshot.dtp> --pattern=<pattern.xml> --save-to=<result.xml>
Reporter.exe compare <snapshot1.dtp> <snapshot2.dtp> --pattern=<pattern.xml> --save-to=<compare.xml>
```

## Vision

Automated performance regression detection:
1. Run test with `-PerformanceProfile` → produces .dtp snapshot
2. Reporter.exe exports XML with method timings
3. Parse XML to identify hot spots
4. Compare against baseline to detect regressions
5. Include in nightly test reports

## Files to Modify

- `ai/scripts/Skyline/Run-Tests.ps1` - Performance profiling integration
- `ai/docs/leak-debugging-guide.md` - Add performance profiling section (or new doc)

## Next Steps — Synthetic Validation

The implementation is complete in `ai/scripts/Skyline/Run-Tests.ps1` (`-PerformanceProfile` flag).
The original real-world test case (TestImportHundredsOfReplicates) is too large and slow.

**Plan**: Use a small, fast unit test with an artificial hot spot to prove the tooling works end-to-end.

1. Pick a short unit test (something that runs in <5 seconds normally)
2. Temporarily add a busy-loop or `Thread.Sleep(5000)` to a method it calls
3. Run with: `pwsh -Command "& './ai/scripts/Skyline/Run-Tests.ps1' -TestName <test> -PerformanceProfile"`
4. Verify the artificial hot spot appears in the top 10 hot spots output
5. Remove the artificial delay
6. Close the TODO

This validates: dotTrace CLI discovery, snapshot capture, Reporter.exe XML export, and hot spot parsing — all without needing a real performance regression.

## Related

- dotMemory integration: PR #3870 (merged)
- FilesView perf regression: TODO-20260102_FilesViewPerfRegression.md
