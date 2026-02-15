# Screenshot Override for Claude Code UI Review

## Branch Information
- **Branch**: `Skyline/work/20260214_screenshot_override`
- **Base**: `master`
- **Created**: 2026-02-14
- **Status**: In Progress
- **GitHub Issue**: (none yet)
- **PR**: [#3981](https://github.com/ProteoWizard/pwiz/pull/3981)

## Objective

Enable Claude Code to capture screenshots of specific Skyline UI states during test execution, so it can review forms, dialogs, and graphs directly without a human taking screenshots.

## Background

The existing screenshot infrastructure (`PauseForScreenShot` / `ScreenshotManager`) captures 2000+ tutorial screenshots but only activates in special modes (pause=-1/-2/-3) designed for human-interactive or full-tutorial workflows. Claude needs a lightweight way to capture **individual** screenshots at specific points during **any** test run.

### Current screenshot modes (TestFunctional.cs)

| PauseSeconds | Mode | Behavior |
|---|---|---|
| 0 (default) | Normal | No screenshots, `_shotManager` is null |
| -1 | `IsPauseForScreenShots` | Manual: shows PauseAndContinueForm, waits for user |
| -2 | `IsCoverShotMode` | Automated: captures cover.png |
| -3 | `IsAutoScreenShotMode` | Fully automated: saves all s-NN.png to tutorial folder |

### Key constraints

- **`Program.SkylineOffscreen`** (line 1956-1957): When true, `PauseForScreenShotInternal` returns immediately. Screenshots require `-ShowUI` (offscreen=off) since `ScreenshotManager` uses GDI `CopyFromScreen`.
- **`_shotManager`** (line 2536-2537): Only initialized when `IsRecordingScreenShots` is true. Normal test runs have `_shotManager == null`.
- **`ScreenshotManager` constructor** (line 258): Accepts null `tutorialPath` gracefully.

## Design

### Core: `ScreenshotOverride` disposable (nested in AbstractFunctionalTest)

A nested class that sets a static field on `AbstractFunctionalTest`. When active, the next `PauseForScreenShot*()` call captures a screenshot to the specified path regardless of screenshot mode.

```csharp
// In AbstractFunctionalTest:
private static string _screenshotOverridePath;

public class ScreenshotOverride : IDisposable
{
    public ScreenshotOverride(string path)
    {
        _screenshotOverridePath = path;
    }

    public void Dispose()
    {
        _screenshotOverridePath = null;
    }
}
```

Usage (wrapping an existing PauseForScreenShot call):
```csharp
using (new ScreenshotOverride(@"C:\proj\ai\.tmp\import-results.png"))
{
    if (!PauseForAllChromatogramsGraphScreenShot("Importing Results form", 90, ...))
        return;
}
```

### Convenience: `TakeScreenshot` method

A simple wrapper around `ScreenshotOverride` + `PauseForScreenShot`:

```csharp
public void TakeScreenshot(string pathToFile)
{
    using (new ScreenshotOverride(pathToFile))
    {
        PauseForScreenShot();
    }
}
```

Could also offer an overload with a Control parameter:
```csharp
public void TakeScreenshot(string pathToFile, Control screenshotForm)
{
    using (new ScreenshotOverride(pathToFile))
    {
        PauseForScreenShot(screenshotForm);
    }
}
```

### Modification to `PauseForScreenShotInternal` (line 1947)

Two changes needed:

**A. Offscreen warning** - Modify the offscreen early-return to warn when an override is active:

```csharp
if (Program.SkylineOffscreen)
{
    if (_screenshotOverridePath != null)
    {
        Console.Error.WriteLine(
            @"[SCREENSHOT] SKIPPED (offscreen, use -ShowUI): " + _screenshotOverridePath);
        _screenshotOverridePath = null;
    }
    return;
}
```

**B. Override check** - Insert after the offscreen check, before the mode conditionals (before `if (IsDemoMode)` at line 1959):

```csharp
if (_screenshotOverridePath != null)
{
    var overridePath = _screenshotOverridePath;
    _screenshotOverridePath = null; // Consume before taking shot
    _shotManager ??= new ScreenshotManager(SkylineWindow, null);
    WaitForGraphs();
    if (screenshotForm == null)
    {
        if (!fullScreen && formType != null)
            screenshotForm = TryWaitForOpenForm(formType);
        screenshotForm ??= SkylineWindow;
        RunUI(() => screenshotForm.Update());
    }
    Thread.Sleep(1500);
    _shotManager.ActivateScreenshotForm(screenshotForm);
    _shotManager.TakeShot(screenshotForm, fullScreen, overridePath, processShot);
    Console.WriteLine(@"[SCREENSHOT] " + overridePath);
    ScreenshotCounter++;
    return;
}
```

## Files to Modify

- **`pwiz_tools\Skyline\TestUtil\TestFunctional.cs`** - All C# changes

Single file. The `ScreenshotOverride` class, `_screenshotOverridePath` field, `TakeScreenshot` methods, and `PauseForScreenShotInternal` modifications all live here.

## Claude Code Workflow

### Workflow A: Ad-hoc screenshot of Skyline main window

```csharp
// Claude adds this line to any test method:
TakeScreenshot(@"C:\proj\ai\.tmp\main-window.png");
```

### Workflow B: Capture a specific UI state at an existing PauseForScreenShot

```csharp
// Claude wraps an existing call:
using (new ScreenshotOverride(@"C:\proj\ai\.tmp\import-dialog.png"))
{
    PauseForScreenShot<ImportResultsDlg>("Import Results");
}
```

### Build & Run

```powershell
# Build
Build-Skyline.ps1

# Run with visible UI (required for screenshots)
Run-Tests.ps1 -TestName TestSomething -ShowUI
```

Claude reads the .png with the Read tool (multimodal), reviews the UI, removes the temporary code when done.

## Tasks

- [x] Add `_screenshotOverridePath` static field to AbstractFunctionalTest
- [x] Add `ScreenShotOverride` nested class to AbstractFunctionalTest
- [x] Add `TakeScreenShot` convenience method(s) to AbstractFunctionalTest
- [x] Add override check in `PauseForScreenShotInternal` via `TakeOverrideScreenShot` helper
- [x] Extract `ResolveScreenShotForm` and `CaptureScreenShot` helpers (DRY)
- [x] Build and verify zero warnings
- [x] Smoke test: added TakeScreenShot to MethodEditTutorialTest, ran with -ShowUI, verified .png captured
- [ ] Run CodeInspection

## Future Enhancements (not this PR)

- **Command-line screenshot by number**: `Run-Tests.ps1 -CaptureShot 14 -ShotPath "ai/.tmp/shot.png"` - capture a specific PauseForScreenShot by its sequence number without modifying test code. Requires wiring a new parameter through TestRunner -> RunTests -> Program -> TestFunctional.
- **Document Claude's screenshot workflow** in `ai/docs/` for future sessions.

## Progress Log

### 2026-02-14 - Planning

Explored screenshot infrastructure: ScreenshotManager, PauseForScreenShotInternal, auto-screenshot mode, offscreen constraints. Designed ScreenshotOverride approach with TakeScreenshot as convenience wrapper.

### 2026-02-14 - Implementation

Implemented ScreenShotOverride, TakeScreenShot, and TakeOverrideScreenShot in TestFunctional.cs. Extracted ResolveScreenShotForm and CaptureScreenShot helpers to keep PauseForScreenShotInternal simple and DRY. Smoke tested with MethodEditTutorialTest - both ScreenShotOverride wrapping an existing PauseForScreenShot and bare TakeScreenShot produced valid .png files.

Bug fix: Run-Tests.ps1 -ShowUI was broken because buildcheck=1 forces offscreen=true in TestRunner. Fixed by skipping buildcheck when -ShowUI is set.
