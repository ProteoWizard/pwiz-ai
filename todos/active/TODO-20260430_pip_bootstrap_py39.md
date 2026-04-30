# TODO-20260430_pip_bootstrap_py39.md

## Branch Information
- **Branch**: `Skyline/work/20260430_pip_bootstrap_py39`
- **Base**: `master`
- **Created**: 2026-04-30
- **Status**: In Progress
- **GitHub Issue**: [#4176](https://github.com/ProteoWizard/pwiz/issues/4176)
- **PR**: [#4177](https://github.com/ProteoWizard/pwiz/pull/4177)
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
- [ ] **Deferred to follow-up issue**: surface captured stderr/stdout from `RunGetPipScriptTask.DoAction` in the thrown exception. Requires a new resource string + `.Designer.cs` update; out of scope for this bug fix.
- [x] Build Skyline.sln Release|x64

### Validation
- [x] Run `TestAlphaPeptDeepBuildLibrary` locally via Run-Tests.ps1 (passed, 155.6s)
- [ ] Code inspection pass
- [x] Open PR, link issue (PR #4177)

## Key Files

- `pwiz_tools/Skyline/Model/Tools/PythonInstaller.cs` — URL constant, `GetPipScriptDownloadUri`, `RunGetPipScriptTask.DoAction` error reporting
- `pwiz_tools/Skyline/TestPerf/AlphapeptdeepBuildLibraryTest.cs` — the failing test (no expected change; just verify it passes)

## Out of Scope (Track Separately)

- **Bumping embedded Python past 3.9.** Python 3.9 has been EOL since October 2025. The pinned URL unblocks today, but a real fix is to ship a supported Python (3.11/3.12). Bigger change because of AlphaPeptDeep wheel pin compatibility — separate issue when prioritized.

## Reference

- Local repro log: `D:\Nightly\SkylineTesterForNightly_trunk\pwiz\pwiz_tools\Skyline\SkylineTester.log`
- Live bootstrap header confirming pip version: fetched 2026-04-30, ships pip 26.1
- PyPA pinned URL pattern: `https://bootstrap.pypa.io/pip/{major.minor}/get-pip.py`
