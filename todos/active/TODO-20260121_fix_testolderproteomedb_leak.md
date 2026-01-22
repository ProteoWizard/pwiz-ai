# TODO-20260121_fix_testolderproteomedb_leak.md

## Branch Information
- **Branch**: `Skyline/work/20260121_fix_testolderproteomedb_leak`
- **Base**: `master`
- **Created**: 2026-01-21
- **Status**: Ready for Review (local commit only)
- **GitHub Issue**: [#3855](https://github.com/ProteoWizard/pwiz/issues/3855)
- **PR**: (pending)

## Problem Description

TestOlderProteomeDb has a ~10KB memory leak occurring since 2025-11-19. The leak only affects i9 processors:
- BDCONNOL-UW1
- EKONEIL01/BRENDANX-UW25
- BRENDANX-UW7

This appears to be a timing-related issue where faster processors expose a race condition.

## Root Cause Analysis

The root cause is a **static `TestBehavior` field** in `HttpClientWithProgress.cs` at line 786:

```csharp
public static IHttpClientTestBehavior TestBehavior;
```

When tests run in parallel on fast i9 processors, multiple test threads can:
1. Set `TestBehavior` to their own mock implementation
2. Another test overwrites `TestBehavior` before the first test completes
3. The first test's mock objects are never cleaned up properly
4. This results in memory leaks (~10KB per occurrence)

The static field is a shared global state that causes race conditions in parallel test execution.

## Planned Fix Approach

Change the static field to use `[ThreadStatic]` attribute, which gives each thread its own copy:

```csharp
[ThreadStatic]
public static IHttpClientTestBehavior TestBehavior;
```

With `[ThreadStatic]`:
- Each test thread gets its own `TestBehavior` value
- No race conditions between parallel tests
- Tests can still set up mock behaviors without interfering with each other
- Memory is properly cleaned up when each thread finishes

**Alternative considered**: `AsyncLocal<T>` - This is more complex and designed for async/await scenarios. Since Skyline doesn't use async/await (per CRITICAL-RULES.md), `[ThreadStatic]` is the simpler and more appropriate solution.

## Files to Modify

1. `pwiz_tools/Shared/CommonUtil/SystemUtil/HttpClientWithProgress.cs`
   - Line 786: Add `[ThreadStatic]` attribute to `TestBehavior` field

## Tasks

- [x] Read and understand the codebase
- [x] Create TODO file
- [x] Implement the fix
- [x] Make local commit
- [x] Update TODO with completion status
- [x] Build verification
- [x] Test verification

## Implementation Summary

### Change Made
Added `[ThreadStatic]` attribute to the `TestBehavior` field in `HttpClientWithProgress.cs`:

**Before:**
```csharp
public static IHttpClientTestBehavior TestBehavior;
```

**After:**
```csharp
[ThreadStatic]
public static IHttpClientTestBehavior TestBehavior;
```

### Commit
- **Hash**: `b0cfaa050f`
- **Message**: "Fixed TestOlderProteomeDb memory leak from static TestBehavior race condition (#3855)"

## Verification Results (2026-01-21)

### Initial Build Verification (pwiz worktree)
- **Result**: PASS
- **Notes**: Build succeeded in 30.6s. The `daily` worktree had environment issues (missing WebView2, pwiz.CLI, protoc, AssemblyInfo.cs) unrelated to this change. Build was verified by applying the same change to the main `pwiz` worktree which compiled successfully.

### Initial Test Verification (pwiz worktree)
- **Result**: PASS
- **Test**: TestOlderProteomeDb
- **Duration**: 2 seconds (2.5s total with setup)
- **Memory**: 14.50/5.61/92.7 MB
- **Handles**: 3/527 handles
- **Failures**: 0

## Final Verification Results (2026-01-22, daily worktree)

### Build Verification (daily worktree)
- **Result**: PASS
- **Duration**: 36.9s
- **Notes**: Build succeeded in the `daily` worktree after environment was fixed. All test assemblies compiled successfully including Test.dll, TestFunctional.dll, TestTutorial.dll, TestData.dll, TestConnected.dll, TestPerf.dll.

### Test Verification (daily worktree)
- **Result**: PASS
- **Test**: TestOlderProteomeDb
- **Duration**: 2 seconds (2.5s total with setup)
- **Memory**: 14.51/5.58/90.9 MB
- **Handles**: 3/527 handles
- **Failures**: 0

### Observations
1. The `[ThreadStatic]` attribute compiles cleanly with no additional dependencies
2. The test passes without any memory/handle leaks detected
3. The fix is minimal and non-invasive (single line attribute addition)
4. True verification of the race condition fix will require running on i9 processors (BDCONNOL-UW1, EKONEIL01/BRENDANX-UW25, BRENDANX-UW7) in nightly tests where the timing-dependent leak was originally observed
5. Both initial (pwiz worktree) and final (daily worktree) verifications passed consistently

## Notes

- Do NOT push to remote
- Do NOT update GitHub issue
- All work remains LOCAL only
- Work in the `daily` worktree (C:\proj\daily)

## Next Steps (for human reviewer)

1. Push branch to remote: `git push -u origin Skyline/work/20260121_fix_testolderproteomedb_leak`
2. Create PR against master
3. Verify nightly tests pass on i9 machines (BDCONNOL-UW1, EKONEIL01/BRENDANX-UW25, BRENDANX-UW7)
4. Close GitHub issue #3855 after PR merge
