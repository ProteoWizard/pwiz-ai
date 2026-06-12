# TODO-20260430_pip_bootstrap_py39.md

## Branch Information
- **Branch**: `Skyline/work/20260430_pip_bootstrap_py39`
- **Base**: `master`
- **Created**: 2026-04-30
- **Status**: Completed (merged 2026-05-03, backported to `Skyline/skyline_26_1`)
- **GitHub Issue**: [#4176](https://github.com/ProteoWizard/pwiz/issues/4176)
- **PR**: [#4177](https://github.com/ProteoWizard/pwiz/pull/4177) — squash-merged as `e5a25cb51`
- **Working Repo**: `C:\Dev\bugfix`

## Objective

Fix `TestPerf.AlphapeptdeepBuildLibraryTest.TestAlphaPeptDeepBuildLibrary` which started failing recently because `https://bootstrap.pypa.io/get-pip.py` now ships pip 26.1, which dropped Python 3.9 support. Skyline's AlphaPeptDeep tool ships embedded Python 3.9.13. Switch to PyPA's version-pinned bootstrap URL so the embedded Python keeps working regardless of what the unpinned bootstrap rolls out next.

## Root Cause Summary

- `PythonInstaller.cs:45` constant `BOOTSTRAP_PYPA_URL = "https://bootstrap.pypa.io/"`
- `PythonInstaller.cs:154` `GetPipScriptDownloadUri` => `"https://bootstrap.pypa.io/get-pip.py"`
- That URL serves the latest pip; pip 26.1 (April 2026) requires Python >= 3.10
- Embedded Python is 3.9.13 (`app.config:939`, `Properties/Settings.settings:915`)
- `python-3.9.13\python.exe get-pip.py` exits non-zero -> `RunGetPipScriptTask.DoAction` throws

Confirmed by fetching the live `get-pip.py` and reading the embedded version comment (`pip (version 26.1)`). PyPA-pinned URL `https://bootstrap.pypa.io/pip/3.9/get-pip.py` currently ships pip 26.0.1 (last 3.9-compatible release) and is maintained long-term.

## Task Checklist

### Setup
- [x] Create GitHub issue #4176
- [x] Create branch `Skyline/work/20260430_pip_bootstrap_py39` in `C:\Dev\bugfix`
- [x] Create this TODO

### Implementation
- [x] Change `BOOTSTRAP_PYPA_URL` to `"https://bootstrap.pypa.io/pip/"` in `PythonInstaller.cs:45`
- [x] Add `PythonMajorMinorVersion` helper that returns `"3.9"` for `PythonVersion = "3.9.13"`
- [x] Update `GetPipScriptDownloadUri` (line 154) to compose `{BOOTSTRAP_PYPA_URL}{PythonMajorMinorVersion}/{GET_PIP_SCRIPT_FILE_NAME}`
- [x] Surface captured stderr/stdout from process-runner failures in the thrown exception
  - Promoted `TeeTextWriter` from `JsonUiService` (private inner) to public `Util/UtilIO.cs`
  - Added `RunProcessOrThrow` static helper in `PythonInstaller` that tees `Writer` + capture and throws with output
  - Refactored all 5 `RunProcess` call sites in `PythonInstaller.cs` (EnableWindowsLongPaths, PipInstall, RunPythonModule, RunGetPipScriptTask, SetupNvidiaLibrariesTask) to use the helper
  - Added new resource string `PythonInstaller_Failed_to_execute_command____0____Output____1__`
  - Verified by temporarily reverting the URL fix; new exception now includes pip's actual `"This script does not work on Python 3.9..."` message
- [x] Build Skyline.sln Release|x64

### Validation
- [x] Run `TestAlphaPeptDeepBuildLibrary` locally via Run-Tests.ps1 (passed, 150.9s after both commits)
- [x] Code inspection pass (build green at every commit)
- [x] Open PR, link issue (PR #4177)
- [x] PR merged (e5a25cb51, 2026-05-03)
- [x] Cherry-picked to release branch `Skyline/skyline_26_1`

## Completion Summary

Merged 2026-05-03 as squash commit `e5a25cb51`. Backported to `Skyline/skyline_26_1` for the 26.1 release line.

**Final scope** (5 commits in PR, squashed at merge):
1. URL fix — `BOOTSTRAP_PYPA_URL` switched to PyPA's version-pinned subpath; `GetPipScriptDownloadUri` resolves to `pip/{major.minor}/get-pip.py` derived from `PythonVersion`
2. Diagnostic improvement — promoted `TeeTextWriter` to `Util/UtilIO.cs`; added `RunProcessOrThrow` static helper that tees `Writer` + capture and includes captured output in `ToolExecutionException`; refactored 5 `RunProcess` call sites to use it; new resource string `PythonInstaller_Failed_to_execute_command____0____Output____1__`
3. Cache invalidation (Copilot review) — `GetPipScriptDownloadPath` now writes `get-pip-{major.minor}.py` so URL changes invalidate any cached `get-pip.py` from the broken unpinned URL
4. Bounded capture (Copilot review) — `RollingTextWriter` private helper caps capture at 32KB tail (pip can stream MBs of output)
5. Reverted ja/zh-CHS resx additions + added `.github/copilot-instructions.md` rule that translations are handled by dedicated translators

**Generality**: All version logic derives from `Settings.Default.PythonEmbeddableVersion`. Bumping Skyline's embedded Python past 3.9 requires no code change in this area.

**Demonstrated diagnostic value**: With URL fix temporarily reverted, the new exception now shows pip's actual error message:
> ERROR: This script does not work on Python 3.9. The minimum supported Python version is 3.10. Please use https://bootstrap.pypa.io/pip/3.9/get-pip.py instead.

## Key Files

- `pwiz_tools/Skyline/Model/Tools/PythonInstaller.cs` — URL fix + `RunProcessOrThrow` helper + 5 call site refactor
- `pwiz_tools/Skyline/Util/UtilIO.cs` — public `TeeTextWriter` (promoted from JsonUiService)
- `pwiz_tools/Skyline/ToolsUI/JsonUiService.cs` — removed duplicate inner `TeeTextWriter`
- `pwiz_tools/Skyline/Model/Tools/ToolsResources.resx` + `.Designer.cs` — new "Failed... Output: ..." string
- `pwiz_tools/Skyline/TestPerf/AlphapeptdeepBuildLibraryTest.cs` — the failing test (no expected change; just verify it passes)

## Out of Scope (Track Separately)

- **Bumping embedded Python past 3.9.** Python 3.9 has been EOL since October 2025. The pinned URL unblocks today, but a real fix is to ship a supported Python (3.11/3.12). Bigger change because of AlphaPeptDeep wheel pin compatibility — separate issue when prioritized.

## Reference

- Local repro log: `D:\Nightly\SkylineTesterForNightly_trunk\pwiz\pwiz_tools\Skyline\SkylineTester.log`
- Live bootstrap header confirming pip version: fetched 2026-04-30, ships pip 26.1
- PyPA pinned URL pattern: `https://bootstrap.pypa.io/pip/{major.minor}/get-pip.py`
