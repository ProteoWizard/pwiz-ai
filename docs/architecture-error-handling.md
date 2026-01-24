# Error Handling Architecture

This document describes error handling patterns in Skyline, focusing on the distinction between user-actionable errors and programming defects. These patterns have been refined over 15+ years of development.

## Core Concept: User Errors vs Programming Defects

Skyline distinguishes between two types of errors:

| Type | Description | User Experience |
|------|-------------|-----------------|
| **User-actionable** | External failures (network, files, permissions) | Friendly message dialog |
| **Programming defect** | Bugs, null refs, invalid state | Bug report dialog with stack trace |

The key function `ExceptionUtil.IsProgrammingDefect()` makes this classification.

## Key Components

### Location Reference

| File | Purpose |
|------|---------|
| `pwiz_tools/Skyline/Util/Util.cs:1665-1811` | `ExceptionUtil` class with classification logic |
| `pwiz_tools/Shared/CommonUtil/SystemUtil/UserMessageException.cs` | Base class for user-friendly exceptions |
| `pwiz_tools/Skyline/Alerts/MessageDlg.cs` | User-friendly error dialogs |
| `pwiz_tools/Skyline/Alerts/ReportErrorDlg.cs` | Bug report dialog |
| `pwiz_tools/Skyline/Program.cs:672` | `ReportException()` entry point |

### IsProgrammingDefect Classification

```csharp
public static bool IsProgrammingDefect(Exception exception)
{
    // User-actionable exceptions with friendly messages
    if (exception is InvalidDataException
        || exception is IOException
        || exception is OperationCanceledException
        || exception is UnauthorizedAccessException
        || exception is UserMessageException)
    {
        return false;  // Show friendly message
    }
    return true;  // Show bug report dialog
}
```

**Returns `false` (user-actionable):**
- `InvalidDataException` - Corrupt/invalid file data
- `IOException` - File system errors (includes subclasses)
- `OperationCanceledException` - User canceled operation
- `UnauthorizedAccessException` - Permission denied
- `UserMessageException` - Custom user-facing errors

**Returns `true` (programming defect):**
- `NullReferenceException`
- `ArgumentException`, `ArgumentNullException`
- `InvalidOperationException`
- `IndexOutOfRangeException`
- Any other exception type

## Exception Hierarchy

### UserMessageException (User-Actionable Base Class)

Use for errors caused by external factors where the user can take action:

```
UserMessageException (pwiz.Common.SystemUtil)
├── WebToolException       - External tool web failures
├── ToolExecutionException - External tool execution errors
└── ToolDeprecatedException - Deprecated tool usage
```

**When to use:**
- Network failures, timeouts
- External tool errors
- Configuration problems user can fix
- File format issues user can resolve

**When NOT to use:**
- Programming errors (use standard exceptions)
- API contract violations (use `ArgumentException`)
- Internal state corruption (let it be a defect)

### IOException Subclasses (User-Actionable)

```
IOException
├── InvalidDataException       - Corrupt file data
├── FileModifiedException      - File changed during operation
├── LineColNumberedIoException - Parse error with location
├── PanoramaException          - Panorama server errors
│   ├── PanoramaServerException
│   └── PanoramaImportErrorException
└── InvalidChemicalModificationException - Invalid chemical formula
```

### Other Exception Categories

```
OperationCanceledException
└── CancelClickedTestException - Test-specific cancellation

ArgumentException
└── UsageException - Command-line argument errors
    ├── ValueMissingException
    ├── ValueInvalidException
    └── ... (many specific validation exceptions)
```

## DisplayOrReportException Pattern

The central function for handling caught exceptions:

```csharp
public static void DisplayOrReportException(
    IWin32Window parent,
    Exception exception,
    string message = null)
{
    if (IsProgrammingDefect(exception))
    {
        // Bug report dialog - user can submit to skyline.ms
        Program.ReportException(exception);
    }
    else
    {
        // Friendly message dialog
        string fullMessage = exception.Message;
        if (!string.IsNullOrEmpty(message))
            fullMessage = TextUtil.LineSeparate(message, fullMessage);
        MessageDlg.ShowWithException(parent, fullMessage, exception);
    }
}
```

### Usage Pattern

```csharp
try
{
    // Operation that might fail
    LoadFile(path);
}
catch (Exception ex)
{
    ExceptionUtil.DisplayOrReportException(this, ex,
        "Error loading the file");
}
```

## WrapAndThrowException Pattern

Used primarily for **cross-thread exception marshalling**. When an exception is caught on a background thread and needs to be re-thrown on the foreground thread, use `WrapAndThrowException` to preserve the original stack trace.

```csharp
public static void WrapAndThrowException(Exception x)
{
    if (x is InvalidDataException)
        throw new InvalidDataException(x.Message, x);
    if (x is IOException)
        throw new IOException(x.Message, x);
    if (x is OperationCanceledException)
        throw new OperationCanceledException(x.Message, x);
    if (x is UnauthorizedAccessException)
        throw new UnauthorizedAccessException(x.Message, x);
    if (x is UserMessageException)
        throw new UserMessageException(x.Message, x);

    // Programming defect - wrap in TargetInvocationException
    throw new TargetInvocationException(x.Message, x);
}
```

### Cross-Thread Exception Pattern

```csharp
Exception savedException = null;

// Background thread catches exception
ActionUtil.RunAsync(() =>
{
    try
    {
        DoWork();
    }
    catch (Exception ex)
    {
        savedException = ex;
    }
});

// Foreground thread re-throws with preserved stack trace
if (savedException != null)
    ExceptionUtil.WrapAndThrowException(savedException);
```

### CRITICAL: Never Re-Throw Directly

```csharp
// BAD - overwrites original stack trace with this location
throw savedException;

// GOOD - preserves original stack trace
throw new IOException(savedException.Message, savedException);

// GOOD - use helper for correct type preservation
ExceptionUtil.WrapAndThrowException(savedException);
```

**Why this matters:** Direct re-throw (`throw ex;`) replaces the original stack trace with the current location, making debugging nearly impossible. Always use `throw new` with the original as `InnerException`, or use `WrapAndThrowException`.

## BackgroundLoader Exception Handling

### Overview

Classes derived from `BackgroundLoader` perform long-running operations on background threads. These operations must report errors across two boundaries:

1. **Threading boundary**: Background thread → Main (UI) thread
2. **Model-View boundary**: Model classes (e.g., `Skyline\Model\*`) → GUI (`SkylineWindow`) or CLI (`CommandStatusWriter`)

The `IProgressMonitor`/`IProgressStatus` pattern handles this marshalling.

### Location Reference

| File | Purpose |
|------|---------|
| `pwiz_tools/Skyline/Model/BackgroundLoader.cs` | Base class for background loaders |
| `pwiz_tools/Shared/CommonUtil/SystemUtil/IProgressMonitor.cs` | Progress monitoring interface |
| `pwiz_tools/Shared/CommonUtil/SystemUtil/ProgressStatus.cs` | Immutable progress state with error support |

### The IProgressStatus.ChangeErrorException Pattern

When a background loader encounters an error that should be reported to the user, it uses `IProgressStatus.ChangeErrorException()`:

```csharp
catch (Exception x)
{
    progressMonitor.UpdateProgress(
        progressStatus.ChangeErrorException(x));
}
```

The UI (or CLI) receives this status update and displays the error appropriately.

### CRITICAL: IsProgrammingDefect in Background Loaders

The base `BackgroundLoader.OnLoadBackground` method has a top-level catch that reports unhandled exceptions as programming defects:

```csharp
// BackgroundLoader.OnLoadBackground (simplified)
try
{
    LoadBackground(container, document, docCurrent);
}
catch (Exception exception)
{
    Program.ReportException(exception);  // Bug report dialog
}
```

**This means**: If a derived class's `LoadBackground` throws an unhandled exception, it will trigger the bug report dialog. This is correct for programming defects.

### Correct Pattern: LibraryManager

`LibraryManager.CallWithSettingsChangeMonitor` demonstrates the correct approach:

```csharp
try
{
    return changeFunc(settingsChangeMonitor);
}
catch (OperationCanceledException)
{
    // User cancelled - expected, just return
    return docCurrent;
}
catch (Exception x)
{
    if (ExceptionUtil.IsProgrammingDefect(x))
    {
        throw;  // Let base class report as bug
    }
    // User-actionable error - report via progress
    settingsChangeMonitor.ChangeProgress(s => s.ChangeErrorException(x));
    return null;
}
```

**Key points:**
1. Check `IsProgrammingDefect(x)` before deciding how to handle
2. **Re-throw** programming defects - let the base class's `ReportException` handle them
3. **Report via ChangeErrorException** only for user-actionable errors

### Problematic Pattern: Wrapping All Exceptions

Some loaders incorrectly wrap ALL exceptions as user-actionable errors:

```csharp
// PROBLEMATIC - treats programming defects as user errors
catch (Exception x)
{
    var message = new StringBuilder();
    message.AppendLine($"Failed updating {name}");
    message.Append(x.Message);
    UpdateProgress(progressStatus.ChangeErrorException(
        new IOException(message.ToString(), x)));  // Wraps NullReferenceException, etc.!
    return null;
}
```

**Problems with this approach:**
- `NullReferenceException`, `ArgumentException`, etc. become user-facing messages
- Programming defects never reach `Program.ReportException`
- Bug reports are never submitted to skyline.ms
- Development team loses visibility into code issues

### BackgroundLoader Classes to Review

| Class | File | Notes |
|-------|------|-------|
| `LibraryManager` | `Model/Lib/Library.cs` | Good example with IsProgrammingDefect |
| `ChromatogramManager` | `Model/Results/Chromatogram.cs` | Uses IsProgrammingDefect |
| `BackgroundProteomeManager` | `Model/Proteome/BackgroundProteomeManager.cs` | Review needed |
| `ProteinMetadataManager` | `Model/Proteome/ProteinMetadataManager.cs` | Review needed |
| `RetentionTimeManager` | `Model/RetentionTimes/RetentionTimeManager.cs` | Review needed |
| `IrtDbManager` | `Model/Irt/IrtDbManager.cs` | Review needed |
| `IonMobilityLibraryManager` | `Model/IonMobility/IonMobilityLibraryManager.cs` | Review needed |
| `OptimizationDbManager` | `Model/Optimization/OptimizationDbManager.cs` | Review needed |
| `MultiFileLoader` | `Model/MultiFileLoader.cs` | Review needed |
| `AutoTrainManager` | `Model/Results/Scoring/AutoTrainManager.cs` | Review needed |

## Exception Text Formatting

### Use ToString(), Not Message + StackTrace

When capturing exception text for logging or reporting:

```csharp
// BAD - loses InnerException chain
string text = exception.Message + "\n" + exception.StackTrace;

// GOOD - preserves entire InnerException chain
string text = exception.ToString();
```

`Exception.ToString()` recursively includes all `InnerException` details, which is critical for debugging wrapped exceptions from reflection calls, async operations, and cross-thread marshalling.

### Capture Location Where Exception Was Caught

`ExceptionUtil.GetExceptionText` captures both the original exception AND where it was caught:

```csharp
public static string GetExceptionText(Exception exception, StackTrace stackTraceExceptionCaughtAt)
{
    StringBuilder stringBuilder = new StringBuilder();
    stringBuilder.AppendLine(exception.ToString());
    if (stackTraceExceptionCaughtAt != null)
    {
        stringBuilder.AppendLine("Exception caught at: ");
        stringBuilder.AppendLine(stackTraceExceptionCaughtAt.ToString());
    }
    return stringBuilder.ToString();
}
```

Usage in `Program.ReportException`:

```csharp
var stackTrace = new StackTrace(1, true);  // Capture where we are now
ReportExceptionUI(exception, stackTrace);  // Include in report
```

This provides two stack traces: where the exception originated AND where it was caught and reported - invaluable for debugging complex call chains.

## Exception Filter Pattern

Modern C# exception filters with `IsProgrammingDefect`:

```csharp
try
{
    ImportFile(path);
}
catch (Exception x) when (!ExceptionUtil.IsProgrammingDefect(x))
{
    // Handle user-actionable errors
    MessageDlg.ShowException(this, x);
}
// Programming defects propagate up and trigger bug report
```

## Program.ReportException

Entry point for reporting programming defects:

```csharp
public static void ReportException(Exception exception)
{
    // In test mode, collect for assertion
    if (TestExceptions != null)
    {
        AddTestException(exception);
        return;
    }

    // Show ReportErrorDlg on UI thread
    var stackTrace = new StackTrace(1, true);
    if (mainWindow != null && !mainWindow.IsDisposed)
    {
        mainWindow.BeginInvoke(
            new Action<Exception, StackTrace>(ReportExceptionUI),
            exception, stackTrace);
    }
}
```

The `ReportErrorDlg`:
- Shows exception details to user
- Captures screenshots (optional)
- Allows attaching .sky file (optional)
- Posts to skyline.ms/home/issues/exceptions (see [exceptions.md](mcp/exceptions.md) for triage system)

## Dialog Classes

### CRITICAL: Never Use .NET MessageBox

**Always use `MessageDlg`, `MultiButtonMsgDlg`, `AlertDlg`, or other `FormEx`/`CommonFormEx`-derived dialogs.** Never use `System.Windows.Forms.MessageBox`.

Why: All Skyline dialogs derive from `FormEx` or `CommonFormEx`, which are instrumented for the testing framework. During tests, dialogs have a timer that causes **test failure** (not a hang) if not dismissed within ~15 seconds. Tests can detect, interact with, and dismiss these dialogs. Using `MessageBox` breaks test automation and causes hangs.

```csharp
// BAD - not testable
MessageBox.Show("Error occurred");

// GOOD - instrumented for testing
MessageDlg.Show(parent, "Error occurred");
```

### Dialog Class Hierarchy

| Class | Purpose |
|-------|---------|
| `MessageDlg` | Simple messages with optional exception details |
| `MultiButtonMsgDlg` | Custom button labels and multiple choices |
| `AlertDlg` | Base class with expandable detail section |
| `ReportErrorDlg` | Bug report submission to skyline.ms |

### MessageDlg Methods

```csharp
// Simple message
MessageDlg.Show(parent, "Operation completed");

// Error icon
MessageDlg.ShowError(parent, "File not found");

// With exception details (expandable) - PREFERRED for exceptions
MessageDlg.ShowException(parent, exception);
MessageDlg.ShowWithException(parent, "Failed to load", exception);

// With Yes/No buttons
DialogResult result = MessageDlg.Show(parent, "Proceed?",
    false, MessageBoxButtons.YesNo);
```

### ShowException vs Show(message)

**Always use `ShowException` or `ShowWithException` for exceptions:**

```csharp
// BAD - loses stack trace
MessageDlg.Show(parent, exception.Message);

// GOOD - preserves stack trace in "More Info"
MessageDlg.ShowException(parent, exception);
MessageDlg.ShowWithException(parent, "Context message", exception);
```

### Clipboard Support

`MessageDlg` provides clipboard functionality for easier error reporting:
- **Copy button** - Copies message and detailed info (including stack trace) to clipboard
- **Ctrl+C** - Keyboard shortcut for the same function

This produces a complete ASCII rendition of the dialog contents, making it easy for users to paste error details into support requests or bug reports.

## Best Practices

### DO

1. **Use UserMessageException** for recoverable external errors:
   ```csharp
   if (!File.Exists(path))
       throw new UserMessageException($"File not found: {path}");
   ```

2. **Use DisplayOrReportException** in catch blocks:
   ```csharp
   catch (Exception ex)
   {
       ExceptionUtil.DisplayOrReportException(this, ex);
   }
   ```

3. **Use exception filters** for clean separation:
   ```csharp
   catch (Exception x) when (!ExceptionUtil.IsProgrammingDefect(x))
   ```

4. **Add context to messages**:
   ```csharp
   catch (IOException ex)
   {
       throw new IOException($"Error reading {filename}: {ex.Message}", ex);
   }
   ```

### DON'T

1. **Don't catch Exception without classification**:
   ```csharp
   // BAD - hides bugs
   catch (Exception) { /* ignore */ }

   // GOOD - only catch user errors
   catch (Exception x) when (!ExceptionUtil.IsProgrammingDefect(x))
   ```

2. **Don't use UserMessageException for bugs**:
   ```csharp
   // BAD - this is a programming error
   if (list == null)
       throw new UserMessageException("List is null");

   // GOOD - let NullReferenceException happen or use Assume
   Assume.IsNotNull(list);
   ```

3. **Don't use .NET MessageBox**:
   ```csharp
   // BAD - not instrumented for testing
   MessageBox.Show("Error");

   // GOOD - testable
   MessageDlg.Show(parent, "Error");
   ```

4. **Don't lose stack traces**:
   ```csharp
   // BAD - loses stack trace
   MessageDlg.Show(parent, exception.Message);

   // GOOD - preserves stack trace
   MessageDlg.ShowException(parent, exception);
   ```

5. **Don't re-throw exceptions directly**:
   ```csharp
   // BAD - overwrites stack trace
   throw savedException;

   // GOOD - preserves original stack trace
   ExceptionUtil.WrapAndThrowException(savedException);
   ```

## Adding New User-Actionable Exceptions

When creating a new exception type that should be user-actionable:

1. **Option A**: Inherit from `UserMessageException`:
   ```csharp
   public class MyToolException : UserMessageException
   {
       public MyToolException(string message) : base(message) { }
   }
   ```

2. **Option B**: Inherit from `IOException` (for I/O-related errors):
   ```csharp
   public class MyFileException : IOException
   {
       public MyFileException(string message) : base(message) { }
   }
   ```

3. **Option C**: If you need a completely new category, update `IsProgrammingDefect`:
   - Add the type check to `IsProgrammingDefect()`
   - Add the type to `WrapAndThrowException()`
   - Document the change

## Testing Exception Handling

During tests, exceptions can be captured:

```csharp
// TestExceptions list collects reported exceptions
Program.TestExceptions = new List<Exception>();

// After test
Assert.AreEqual(0, Program.TestExceptions.Count,
    "Unexpected exceptions reported");
```

## Related Documentation

- [mcp/exceptions.md](mcp/exceptions.md) - Exception triage system (skyline.ms reports)
- [architecture-data-model.md](architecture-data-model.md) - Document model and immutability
- [debugging-principles.md](debugging-principles.md) - Investigation techniques
- [testing-patterns.md](testing-patterns.md) - Test infrastructure
