# TODO-20260724_enumwindows_static_callback.md

## Branch Information
- **Branch**: `Skyline/work/20260724_enumwindows_static_callback`
- **Worktree**: `sky_fixes`
- **Base**: `master`
- **Created**: 2026-07-24
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (pending)

## Problem

`User32.EnumWindows()` / `EnumChildWindows()` / `EnumThreadWindows()` each allocated a NEW
closure delegate on every call:

```csharp
public static IEnumerable<IntPtr> EnumWindows()
{
    var handles = new List<IntPtr>();
    EnumWindows((hwnd, lparam) => { handles.Add(hwnd); return true; }, IntPtr.Zero);
    return handles;
}
```

The P/Invoke marshaller builds a native thunk for each delegate it marshals, so a new delegate
per call is native churn on a very hot path — the connector enumerates windows on every
`GetOpenForms`, and `DialogWatcher`'s wait loop polls it continuously.

Found while investigating the native-dialog heap leak
([[TODO-20260723_native_dialog_leak_iterations]]); it is NOT that leak (far too small to
explain it), but it is real and worth fixing on its own.

## Change

The three enumerations take an `lParam` that Windows passes back to the callback untouched. Use
it: allocate a `GCHandle` to the list, pass it as `lParam`, and make the callback a `static`
method that unwraps it — so ONE delegate instance serves the whole process.

```csharp
private static readonly EnumWindowsProc COLLECT_WINDOW_HANDLES = CollectWindowHandle;

private static bool CollectWindowHandle(IntPtr hwnd, IntPtr lParam)
{
    ((List<IntPtr>) GCHandle.FromIntPtr(lParam).Target).Add(hwnd);
    return true;
}
```

Each wrapper does `GCHandle.Alloc(handles)` → passes `GCHandle.ToIntPtr(...)` → `Free()` in a
`finally`. A normal (unpinned) handle is correct: the handle's token is passed, not the object
address, so nothing needs pinning.

Also makes the three wrappers **thread-safe** — better than a `[ThreadStatic]` list would be,
since the callback keeps no state at all and each call carries its own list through `lParam`.
That matters here: the connector enumerates from the pipe/test thread while the UI thread is busy.

## Measured

Real `pwiz.CommonUtil` path, 20,000 calls:

| | growth | shape |
|---|---:|---|
| before (per-call lambda) | 76 KB | drifting, noisy (93 -> 51 -> 76 KB) |
| after (static + lParam) | 4 KB | flat; plateaued at 8k calls |

## Verification

- Full solution builds with no errors or warnings.
- `TestNativeMessageBox`, `TestNativeFileDialog`, `TestMcpConnectorBackgroundDialog`,
  `TestMcpConnectorFormThreading` pass — all depend on window enumeration returning correct
  results, so they would break immediately if the GCHandle unwrapping were wrong.
- A probe compiled against the built assembly saw 127,400 handles across 200 enumerations
  (~637 windows each), confirming the enumeration still returns the same results.

## Files Changed

- `pwiz_tools/Shared/CommonUtil/SystemUtil/PInvoke/User32.cs`
