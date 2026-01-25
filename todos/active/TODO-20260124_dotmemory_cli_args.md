# TODO-20260124_dotmemory_cli_args.md

## Branch Information
- **Branch**: `Skyline/work/20260124_dotmemory_cli_args`
- **Base**: `master`
- **Created**: 2026-01-24
- **Status**: PR Created
- **GitHub Issue**: (none)
- **PR**: [#3870](https://github.com/ProteoWizard/pwiz/pull/3870)

## Objective

Add TestRunner command-line arguments to control existing dotMemory snapshot properties,
and integrate dotMemory CLI into Run-Tests.ps1 for scripted memory profiling.

## Background

- `RunTests.cs` already has properties: `DotMemoryWarmupRuns`, `DotMemoryWaitRuns`, `DotMemoryCollectAllocations`
- `TakeDotMemorySnapshotIfNeeded()` method works when running under dotMemory
- **Missing:** CLI arguments to set these properties from command line
- **Missing:** Run-Tests.ps1 integration with dotMemory CLI

## Tasks

### TestRunner CLI Arguments
- [x] Add CLI args to `commandLineOptions` string in Program.cs
- [x] Extract args in `RunTestPasses` method
- [x] Set properties on RunTests instance after construction

### Run-Tests.ps1 Integration
- [x] Add `-MemoryProfile` switch and related parameters
- [x] Add dotMemory CLI discovery (searches ~/.claude-tools/dotMemory/)
- [x] Build correct dotMemory CLI command with `--use-api` flag
- [x] Fix path logic to use `$PSScriptRoot` (works in sibling mode)

### Installation
- [x] Create `ai/scripts/Install-DotMemory.ps1` script
- [x] Add to `ai/docs/new-machine-setup.md` as optional tool

### Documentation
- [x] Update `ai/docs/leak-debugging-guide.md` - mark CLI args as implemented

### Verification
- [x] Build solution to verify no compile errors
- [x] Test memory profiling workflow end-to-end

## New TestRunner CLI Arguments

```
dotmemorywaitruns=N        # Iterations between snapshots (enables profiling)
dotmemorywarmup=N          # Warmup iterations before first snapshot (default: 5)
dotmemorycollectallocations=on/off  # Capture allocation stack traces
```

## Run-Tests.ps1 Usage

```powershell
# Basic memory profiling (warmup=5, wait=10 iterations between snapshots)
Run-Tests.ps1 -TestName TestOlderProteomeDb -MemoryProfile -Loop 20

# Custom warmup and wait runs
Run-Tests.ps1 -TestName TestOlderProteomeDb -MemoryProfile -MemoryProfileWarmup 2 -MemoryProfileWaitRuns 5 -Loop 10

# With allocation stack traces
Run-Tests.ps1 -TestName TestOlderProteomeDb -MemoryProfile -MemoryProfileCollectAllocations -Loop 20
```

Output: `.dmw` workspace file in `ai/.tmp/memory-{timestamp}.dmw`

## Limitations

dotMemory CLI produces binary `.dmw` workspace files that require the GUI to analyze.
There is no text/JSON export capability (unlike dotCover). To analyze results:
1. Open dotMemory GUI
2. Open the workspace file
3. Compare snapshots to identify leaks

## Future Vision

When JetBrains adds JSON export to dotMemory CLI (feature request pending), extend with:
- Automated analysis and reporting
- Per-test leak detection across entire test suite
- Integration with nightly test reports

## Files Modified

- `pwiz_tools/Skyline/TestRunner/Program.cs` - CLI argument handling
- `ai/scripts/Skyline/Run-Tests.ps1` - Memory profiling integration
- `ai/scripts/Install-DotMemory.ps1` - Installation script (new)
- `ai/docs/leak-debugging-guide.md` - Documentation updates
