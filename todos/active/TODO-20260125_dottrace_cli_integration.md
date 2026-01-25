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
- [ ] Document Reporter.exe capabilities and XML output format
- [ ] Understand dotTrace CLI snapshot format (.dtp files)
- [ ] Determine if pattern file is needed for useful reports

### Implementation
- [ ] Add `-PerformanceProfile` switch to Run-Tests.ps1
- [ ] Add dotTrace CLI discovery (searches JetBrains installation paths)
- [ ] Build dotTrace CLI command for profiling
- [ ] Call Reporter.exe to generate XML report
- [ ] Parse XML to extract hot spots / timing data

### Verification
- [ ] Test with TestImportHundredsOfReplicates (known perf-sensitive test)
- [ ] Verify XML output shows method timing data
- [ ] Compare before/after if regression is reintroduced

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

## Related

- dotMemory integration: PR #3870 (merged)
- FilesView perf regression: TODO-20260102_FilesViewPerfRegression.md
