# TODO-20260102_safebeginvoke_toctou.md

## Branch Information
- **Branch**: `Skyline/work/20260102_safebeginvoke_toctou`
- **Created**: 2026-01-02
- **Status**: Complete - Merged
- **PR Merged**: 2026-02-04 (PST)
- **Cherry-pick**: [#3948](https://github.com/ProteoWizard/pwiz/pull/3948) (merged to Skyline/skyline_26_1)
- **GitHub Issue**: [#3738](https://github.com/ProteoWizard/pwiz/issues/3738)
- **PR**: [#3743](https://github.com/ProteoWizard/pwiz/pull/3743)
- **Related**: PR #3739 (Sprint 1 fix), TODO-20251227_filestree_deadlock.md, #3934 (FilesTree shutdown deadlock)

## Objective

Fix TOCTOU (time-of-check-to-time-of-use) race condition in `SafeBeginInvoke` that can still cause deadlocks even after the Sprint 1 fix.

## Problem Analysis

### The Race Condition

From PR #3739 discussion (Nick Shulman & Brendan MacLean):

```csharp
public static bool SafeBeginInvoke(Control control, Action action)
{
    if (control == null || !control.IsHandleCreated)  // <- Check
        return false;
    try
    {
        control.BeginInvoke(action);  // <- Use: handle can be destroyed between check and here
        return true;
    }
    catch (Exception)
        return false;
}
```

**Critical insight from Brendan**: The try/catch does NOT protect against deadlock. When `BeginInvoke` is called after handle destruction begins, .NET attempts to **recreate the handle**, and that recreation can deadlock the UI thread. There's no exception to catch - just a hang.

### Evidence

Nick found another hang in run 79688 where `BackgroundActionService.RunUI` (which uses `SafeBeginInvoke`) was on the callstack:
https://skyline.ms/home/development/Nightly%20x64/testresults-showRun.view?runId=79688

## Proposed Solution

Add infrastructure to form base classes that signals early shutdown, then check it in `SafeBeginInvoke`.

### Step 1: Extract IClosingAware interface

```csharp
public interface IClosingAware
{
    bool IsClosingOrDisposing { get; }
}
```

### Step 2: Implement on CommonFormEx and DockableFormEx

Both form base classes implement the same pattern:
- `volatile bool _isClosingOrDisposing` field
- Set in `OnFormClosing` (after base call, if not cancelled), `OnHandleDestroyed`, and `Dispose`
- This covers both `CommonFormEx` dialogs and `DockableFormEx` docked panels (like `FilesTreeForm`)

### Step 3: Update SafeBeginInvoke

```csharp
var parentForm = control.FindForm();
if (parentForm is IClosingAware closingAware && closingAware.IsClosingOrDisposing)
    return false;
```

### Why This Helps

1. **Setting the flag in OnFormClosing gives real margin** - the flag is set well before the handle is actually destroyed
2. **The volatile keyword ensures visibility** across threads without locks
3. **Shrinks the race window dramatically** - from "anytime after IsHandleCreated check" to "microseconds between flag check and BeginInvoke while UI thread is simultaneously in the flag-setting code"

### Limitations

This isn't mathematically airtight - there's still a tiny race window. But hitting it would require extremely precise timing that's essentially impossible in normal operation.

## Tasks

- [x] Create branch `Skyline/work/20260102_safebeginvoke_toctou`
- [x] Review CommonFormEx current implementation
- [x] Review SafeBeginInvoke current implementation
- [x] Add `_isClosingOrDisposing` field and property to CommonFormEx
- [x] Override OnFormClosing in CommonFormEx
- [x] Override OnHandleDestroyed in CommonFormEx
- [x] Update Dispose in CommonFormEx
- [x] Update SafeBeginInvoke to check IsClosingOrDisposing
- [x] Run FilesTree tests
- [x] Run broader test suite to verify no regressions (1000 tests passed)
- [x] Create PR
- [x] Extract `IClosingAware` interface so SafeBeginInvoke works with any form base class
- [x] Add `IsClosingOrDisposing` to `DockableFormEx` (covers docked panels like FilesTreeForm)
- [x] Update SafeBeginInvoke to check `IClosingAware` instead of `CommonFormEx`
- [x] Improved XML doc and TOCTOU comments on SafeBeginInvoke
- [x] Run FilesTree coverage tests (4 tests passed)

## Key Files

- `pwiz_tools/Shared/CommonUtil/SystemUtil/CommonFormEx.cs` - IClosingAware interface and CommonFormEx implementation
- `pwiz_tools/Shared/CommonUtil/SystemUtil/CommonActionUtil.cs` - SafeBeginInvoke checks IClosingAware
- `pwiz_tools/Skyline/Util/DockableFormEx.cs` - IClosingAware implementation for docked panels

## References

- PR #3739 discussion: https://github.com/ProteoWizard/pwiz/pull/3739
- Nick's safe pattern example: `pwiz.Common.SystemUtil.Caching.Receiver` class
- Nick's hang evidence: https://skyline.ms/home/development/Nightly%20x64/testresults-showRun.view?runId=79688

## Progress Log

### 2026-01-02 - Session 1
- Created branch from master
- Reviewed CommonFormEx.cs and CommonActionUtil.cs current implementations
- Implemented the fix:
  - Added `_isClosingOrDisposing` volatile field and `IsClosingOrDisposing` property to CommonFormEx
  - Added `OnFormClosing` override (sets flag after base call if not cancelled)
  - Added `OnHandleDestroyed` override (belt-and-suspenders)
  - Updated `Dispose` to set flag before base call
  - Updated `SafeBeginInvoke` to check parent form's `IsClosingOrDisposing` flag
- Full test suite passed (1000 tests, English)
- Created PR

### 2026-02-04 - Session 2
- Issue #3934 revealed SafeBeginInvoke check only covered CommonFormEx, not DockableFormEx
- FilesTreeForm inherits DockableFormEx (not CommonFormEx), so the TOCTOU fix didn't apply
- Extracted `IClosingAware` interface from the pattern
- Added same IsClosingOrDisposing implementation to DockableFormEx
- Updated SafeBeginInvoke to check IClosingAware interface instead of CommonFormEx concrete type
- Improved XML doc on SafeBeginInvoke to document return value contract
- Added TOCTOU comments (TIME-OF-CHECK / TIME-OF-USE annotations)
- FilesTree coverage tests passed (TestFilesModel, TestFilesTreeFileSystem, TestFilesTreeForm, TestSkylineWindowEvents)
