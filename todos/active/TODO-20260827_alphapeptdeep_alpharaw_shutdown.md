# TODO-20260827_alphapeptdeep_alpharaw_shutdown.md

## Branch Information
- **Branch**: `Skyline/work/20260827_alphapeptdeep_alpharaw_shutdown`
- **Base**: `master` (bd94e8a37)
- **Created**: 2026-08-27
- **Status**: In progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (not opened)
- **Cherry-pick**: Yes — `Cherry pick to release` label (Nick's call, 2026-08-27).
  We are in post-release patch mode, where the default is no cherry-pick, but all
  three criteria hold: released 26.1 users installing AlphaPeptDeep today get
  alpharaw 0.7.0 and a library build that always fails; the fixed code exists on
  `Skyline/skyline_26_1` (which already carries the xxhash pin, so the previous
  break of this kind was cherry-picked too).

## Objective

Fix the nightly failure in `TestAlphaPeptDeepBuildLibrary`, which began failing
on 2026-08-27 after an upstream Python dependency published a breaking change.
Second occurrence of the same class of break as
[TODO-20260816_alphapeptdeep_xxhash_pin](../completed/TODO-20260816_alphapeptdeep_xxhash_pin.md).

## Root Cause

Not a Skyline regression, and not a change in AlphaPeptDeep. `peptdeep cmd-flow`
does all of its work correctly and writes every output file, then crashes on the
way out and returns exit code `0xE0434352` (unhandled CLR exception). Skyline's
`ProcessRunner` sees the non-zero exit code and reports "Failed to build library
by executing the AlphaPeptDeep cmd-flow command", which raises a `MessageDlg`
the test times out waiting for.

The crash comes from **alpharaw 0.7.0**, released 2026-08-26 — the day before
the nightly failed. `peptdeep` requires only `alpharaw>=0.2.0`, so pip resolved
to 0.7.0 on the first env built after that.

alpharaw 0.7.0 rewrote `alpharaw/raw_access/clr_utils.py` and added:

```python
# clr_loader's mono backend errors during its atexit unload ...
atexit.unregister(pythonnet.unload)
```

`pythonnet.unload` is what performs the orderly shutdown —
`Python.Runtime.Loader.Shutdown("full_shutdown")` while the interpreter is still
alive, then `_RUNTIME.shutdown()`. Without it the CLR tears itself down after
`Py_Finalize`, and `PythonEngine.Shutdown()` calls `PyGILState_Ensure()` against
a dead interpreter:

```
Unhandled Exception: System.AccessViolationException: Attempted to read or write protected memory.
   at Python.Runtime.Runtime.PyGILState_Ensure()
   at Python.Runtime.Py.GIL()
   at Python.Runtime.PythonEngine.Shutdown()
```

Nothing in the peptdeep library workflow needs alpharaw's .NET readers; the CLR
is loaded purely as an import side effect, and only its shutdown is fatal.

### Two facts that are easy to get wrong

Both were established by probing the real `peptdeep.exe` (temporary
`sitecustomize.py` in the venv reporting CLR state at `atexit`), after an
import-only probe gave misleading answers and cost a failed test run.

**1. `ALPHARAW_DOTNET_RUNTIME` does not select the runtime.**
`alpharaw/__init__.py` `register_all_readers()` imports `.sciex` before
`.thermo`, and `pysciexwifffilereader.py` runs a bare `import clr` *before*
`from .clr_utils import ...`. So Python.NET is already loaded — via its default,
netfx on Windows — before `clr_utils` selects anything, and
`pythonnet.load()` begins with `if _LOADED: return`. alpharaw's call is a silent
no-op, and it then records the runtime it *asked* for as though it had won.
alpharaw's own `pythermorawfilereader.py` carries the comment "MUST be imported
before `clr`"; the sibling module gets the order wrong.

**2. The AccessViolation is specific to .NET Framework hosting.** Under CoreCLR
the missing unload hook is harmless.

Measured, full `peptdeep cmd-flow` runs:

| setting | `alpharaw.DOTNET_RUNTIME` | actual runtime | exit |
|---|---|---|---|
| *(nothing set)* | `'netfx'` | .NET Framework | **127** |
| `ALPHARAW_DOTNET_RUNTIME=coreclr` | `'coreclr'` | **.NET Framework** | **127** |
| `PYTHONNET_RUNTIME=coreclr` | `'netfx'` | **CoreCLR** | 0 |
| `ALPHARAW_DOTNET_RUNTIME=none` | `None` | .NET Framework | 0 |
| both (`coreclr` + `none`) | `None` | CoreCLR | 0 |
| both, `DOTNET_ROOT` emptied | `None` | none loaded | 0 |

The two middle-column values disagree with reality in opposite directions, which
is the whole trap.

Note the fourth row: `ALPHARAW_DOTNET_RUNTIME=none` alone does **not** keep the
CLR out of the process — the Sciex reader's bare `import clr` still loads netfx.
It works for a different reason: the unrecognized name makes
`_load_dotnet_runtime()` raise, which skips the entire `try` block *including*
the `atexit.unregister` call, so the orderly shutdown hook survives.

Every crashing run still wrote a complete library first, identical in size to a
clean run's (`predict.speclib.hdf` 247207 bytes, `predict.speclib.tsv` 58952).

## Fix

`pwiz_tools/Skyline/Model/Lib/AlphaPeptDeep/AlphapeptdeepLibraryBuilder.cs` —
set `ALPHARAW_DOTNET_RUNTIME=none` on the environment of both peptdeep child
processes, via a new `CreatePeptdeepStartInfo` helper that the two callers
(`PrepareSettingsFile`, `ExecutePeptdeep`) now share.

`none` is not a runtime and never reaches one. It makes alpharaw's runtime
lookup raise, which skips the whole `try` block containing the
`atexit.unregister` call, so Python.NET's own shutdown hook survives and runs
while the interpreter is still alive. The CLR still gets loaded (by the Sciex
reader's bare `import clr`) — it just shuts down cleanly.

Does not freeze the dependency. Releases before 0.7.0 ignore the variable and do
not have the bug either way.

### Why not host on .NET Core

`PYTHONNET_RUNTIME=coreclr` also avoids the crash and was implemented and tested
(passed, 259 sec), but was backed out. .NET Core is not part of Windows — Windows
10/11 ship .NET Framework 4.x only — so the setting takes effect on developer and
nightly machines (which have .NET installed) and does nothing on most users'
machines. That would leave the nightly exercising a path users never run. With
`ALPHARAW_DOTNET_RUNTIME=none` alone, both get netfx plus an orderly shutdown —
the same path everywhere.

Revisit when Skyline itself is on .NET. Note it will not become effective
automatically: if Skyline ships self-contained, no shared runtime is installed
and clr_loader still will not find hostfxr, so `DOTNET_ROOT` would have to point
at Skyline's own runtime directory from this same helper. If the installer brings
the shared runtime instead, `PYTHONNET_RUNTIME=coreclr` starts working on its own.

## Verification

- Build succeeded (Debug).
- Full `peptdeep cmd-flow` command line from the nightly stack trace, alpharaw
  0.7.0, variable set: exit 0, library generated.
- `TestAlphaPeptDeepBuildLibrary`: passed, 0 failures, 238 sec (Debug/en-US,
  offscreen).
- Configurations implemented and tested, then backed out: `PYTHONNET_RUNTIME=coreclr`
  plus this variable (passed, 259 sec); the `alpharaw==0.6.1` pin (passed, 266 sec).

## Blocker: a second failure this fix exposes

With the fix in, the cmd-flow step succeeds and the test runs ~60 sec further,
then fails intermittently loading the document library `Rat_plasma.sky`
references:

```
Failed loading library '...\AlphapeptdeepBuildLibraryTest\rat_consensus_final_true_lib.blib'
---> System.Data.SQLite.SQLiteException: unable to open database file
   at pwiz.Skyline.Util.PooledSqliteConnection.Connect()
   at pwiz.Skyline.Model.Lib.BiblioSpecLiteLibrary.ProteinsBySpectraID()
   at pwiz.Skyline.Model.Lib.BiblioSpecLiteLibrary.ReadFromDatabase(...)
```

**Roughly 50% reproducible** — 4 passes / 4 failures on 2026-08-27 with the fix
in place (passes at 266, 238, 259, 208 sec).

Not caused by this change: the env var is set on the peptdeep child process,
while this is SQLite inside Skyline's own process. Clean master cannot be
compared — it fails earlier, at the cmd-flow step, so it never reaches here.

Ruled out:
- **The file.** Freshly extracted from the test zip, valid `SQLite format 3`
  header, 65536 bytes, all seven tables, opens from Python, file and directory
  both writable.
- **Leftover state.** Two stale copies of the test directory were deleted; the
  re-extracted run failed identically.
- **Concurrent processes.** The Visual Studio `testhost.exe` had already exited;
  the running `Skyline-daily.exe` is a developer instance on a different build
  with an unrelated document.
- **The connection string.** `ToFullPath=false` with a correct absolute path.

Unexplained. Note `DoTest` does `RunUI(() => OpenDocument(...))` without waiting
for the document to load, so the document library loads in the background while
the test builds libraries — a race, but the reason the open fails is still not
established.

Worth weighing: `query_test_history` records no failures for this test, and this
path was reachable and passing before alpharaw 0.7.0 shipped. A 50% flake would
have shown up in the nightly, so this is more likely local to this machine or
new, rather than a long-standing race. **Merging the fix alone would take the
nightly from always red to intermittently red.**

The test sets `IsCleanPythonMode => true`, so it deletes the tools Python
directory and rebuilds the venv from scratch each run — it resolves alpharaw to
0.7.0, so these runs exercise the real broken version.

## Alternatives not taken

- **Pin `alpharaw` to 0.6.1** in `CreatePythonInstaller`, matching the existing
  numpy 1.26.4 and xxhash 3.5.0 entries. Verified working, but it would be the
  third frozen dependency in that list and costs every future alpharaw fix.
- **`ALPHARAW_DOTNET_RUNTIME=coreclr`** — implemented and **failed the test**.
  Inert for runtime selection, per fact 1 above.
- **`PYTHONNET_RUNTIME=coreclr`** — works, but only where .NET Core is installed;
  see "Why not host on .NET Core" above. Alone it is worse than useless on a
  machine without it: the early `import clr` fails and alpharaw then falls back
  to netfx and crashes.
- **Accept the exit code**: pass an `outputAndExitCodeAreGoodFunc` to
  `ProcessRunner.Run` in `ExecutePeptdeep` that treats the run as successful
  when the output library exists. The most honest description of what happens —
  the process really did succeed — but it widens what counts as success and
  could mask a later real failure.

## Follow-up

- Report both defects upstream to MannLabs:
  1. `atexit.unregister(pythonnet.unload)` turns a spurious Mono traceback into
     an AccessViolation and a non-zero exit code under .NET Framework. Narrow
     fix: unregister only when the loaded runtime is Mono.
  2. `ALPHARAW_DOTNET_RUNTIME` has no effect when the Sciex reader is imported,
     because its bare `import clr` loads Python.NET first. Fix: import
     `clr_utils` before `clr` there, as `pythermorawfilereader.py` already does.
- Third break of this kind in the AlphaPeptDeep package list. Skyline installs
  `peptdeep` unpinned, so any package in that tree can break the nightly on any
  night. The xxhash TODO already raised `peptdeep[stable]` as an option (blocked
  because it pins `torch==2.5.1`, colliding with the CUDA-specific torch
  install). Still unclaimed, and now has one more data point behind it.

## Notes

- The local Release tools venv was left with `alpharaw==0.7.0` (master's
  unpinned resolution) after these experiments. `IsCleanPythonMode` rebuilds it
  on the next test run either way.
