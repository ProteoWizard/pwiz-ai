# TODO-20260113_python_venv_external_tools.md

## Branch Information
- **Branch**: `Skyline/work/20260113_PythonExternalTools`
- **Base**: `master`
- **Created**: 2026-01-13
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (pending)

## Objective

Modify external tool installation to use Python virtual environments instead of system-wide Python installation. Each tool gets its own isolated virtual environment, enabling:
- Package isolation between tools
- No conflicts when different tools need different package versions
- Cleaner tool management

## Context

Currently, external tools that require Python use `PythonInstallerLegacyDlg` which:
- Installs Python system-wide via MSI
- Installs packages globally
- Uses Windows Registry to find Python

The newer `PythonInstaller` class already supports:
- Embeddable Python (no MSI, no admin needed)
- Virtual environments per tool
- pip package management within venvs

## Implementation Plan

### Phase 1: Interface Changes ✅

- [x] Add `virtualEnvironmentName` parameter to `IUnpackZipToolSupport.InstallProgram`
- [x] Update `ToolInstaller.cs` to pass `PackageIdentifier` as venv name
- [x] Update `ToolInstallUI.cs` `InstallZipToolHelper` to match new signature
- [x] Update `InstallProgram` delegate definition

### Phase 2: Python Installation Logic ✅

- [x] Modify `SkylineWindow.InstallProgram` to use `PythonInstaller` instead of `PythonInstallerLegacyDlg`
- [x] Convert `ToolPackage` collection to `PythonPackage` collection
- [x] Return venv Python path instead of system Python path
- [x] Handle immediate window output for pip operations

### Phase 3: Upgrade Support ✅

- [x] Add `CopyPythonDirectory` method to `Program.cs`
- [x] Call it from `CopyOldTools` during Skyline upgrades
- [x] Ensure all venvs under `Tools\Python\` are copied

### Phase 4: Command Line Support ✅

- [x] Check `CommandLine.cs` for `AddZipToolHelper.InstallProgram` usage
- [x] Update if necessary to match new interface

### Phase 5: Testing

- [x] Create `PythonExternalToolTest` functional test
- [x] Update test files to match new interface signatures
- [ ] Verify new tool installation creates correct venv
- [ ] Test Skyline upgrade copies Python directory
- [ ] Test tool works after upgrade
- [ ] Test multiple tools with separate venvs

## Key Files

| File | Purpose |
|------|---------|
| `pwiz_tools/Skyline/Model/Tools/ToolInstaller.cs` | Interface definition, tool unpacking |
| `pwiz_tools/Skyline/Model/Tools/PythonInstaller.cs` | New venv-based Python installer |
| `pwiz_tools/Skyline/ToolsUI/PythonInstallerUI.cs` | UI for new installer |
| `pwiz_tools/Skyline/ToolsUI/PythonInstallerLegacyDlg.cs` | Old installer (being replaced) |
| `pwiz_tools/Skyline/ToolsUI/ToolInstallUI.cs` | Install helper, delegate |
| `pwiz_tools/Skyline/Skyline.cs` | `InstallProgram` method |
| `pwiz_tools/Skyline/Program.cs` | `CopyOldTools` for upgrades |
| `pwiz_tools/Skyline/TestFunctional/PythonExternalToolTest.cs` | Functional test for Python tool installation |

## Design Decisions

1. **Per-tool venvs** (not shared) - User chose isolation over simplicity
2. **Copy entire Python directory on upgrade** - Option C from discussion
3. **Use PackageIdentifier as venv name** - Already available in tool-inf/info.properties
4. **Instance-specific Python version** - Each tool can specify its own Python version

## Technical Implementation

### Instance-Specific Python Version Support

Added to `PythonInstaller.cs` to allow different tools to use different Python versions:

```csharp
// Instance-specific Python version (allows different tools to use different Python versions)
private readonly string _instancePythonVersion;

// Instance properties that use the tool's requested Python version
public string InstancePythonVersion => _instancePythonVersion ?? PythonVersion;
public string InstancePythonVersionDir => Path.Combine(PythonRootDir, InstancePythonVersion);
// ... and related Instance* properties for paths
```

The constructor now accepts an optional `pythonVersion` parameter:
```csharp
public PythonInstaller(IEnumerable<PythonPackage> packages,
    TextWriter writer, string virtualEnvironmentName, string pythonVersion = null)
```

All task classes (download, extract, pip install, virtualenv creation) now use `Instance*` properties instead of static properties, enabling per-tool Python version isolation.

## Edge Cases to Handle

- Tool without `PackageIdentifier` - fall back to `PackageName`
- Existing system Python - should still work for legacy tools
- venv path length - relies on Windows LongPathsEnabled setting

## Progress Log

### 2026-01-13
- Initial analysis of codebase
- Identified all relevant files and code paths
- User chose per-tool venvs with interface modification
- Created implementation plan
- **Implementation completed:**
  - Modified `IUnpackZipToolSupport.InstallProgram` interface to add `virtualEnvironmentName` parameter
  - Updated `ToolInstaller.cs` to pass tool's `PackageIdentifier` as venv name
  - Updated `ToolInstallUI.cs` delegate and helper to match new signature
  - Replaced `PythonInstallerLegacyDlg` with `PythonInstaller` in `Skyline.cs`
  - Added `CopyPythonDirectory` and `FindOldPythonDirectory` methods to `Program.cs`
  - Updated `CommandLine.cs` `AddZipToolHelper.InstallProgram` to match interface
  - Fixed test files: `MSstatsTutorialTest.cs`, `QuasarTutorialTest.cs`, `InstallToolsTest.cs`, `ToolStoreDlgTest.cs`
- Build passes (Release|x64)

- **Added `PythonExternalToolTest` functional test:**
  - Created `PythonExternalToolTest.cs` test class
  - Added test data: `SkylinePRISM.zip` (Python-based external tool)
  - Added test data: `ThreeReplicates.sky`, `.skyd`, `.blib` (test document)
  - Test verifies:
    - Installing a Python external tool creates virtual environment
    - Success message is displayed
    - Tool appears in Tools menu and can be invoked

## Commits

| Hash | Message |
|------|---------|
| 9b3c0c4d5 | Python virtual environment support for external tools |
| c9ffbd0f9 | PythonExternalToolTest |

## Files Modified (vs master)

```
pwiz_tools/Skyline/CommandLine.cs
pwiz_tools/Skyline/Model/Tools/PythonInstaller.cs
pwiz_tools/Skyline/Model/Tools/ToolInstaller.cs
pwiz_tools/Skyline/Program.cs
pwiz_tools/Skyline/Skyline.cs
pwiz_tools/Skyline/TestFunctional/InstallToolsTest.cs
pwiz_tools/Skyline/TestFunctional/PythonExternalToolTest.cs (new)
pwiz_tools/Skyline/TestFunctional/PythonExternalToolTest.data/ (new)
pwiz_tools/Skyline/TestFunctional/TestFunctional.csproj
pwiz_tools/Skyline/TestFunctional/ToolStoreDlgTest.cs
pwiz_tools/Skyline/TestTutorial/MSstatsTutorialTest.cs
pwiz_tools/Skyline/TestTutorial/QuasarTutorialTest.cs
pwiz_tools/Skyline/ToolsUI/ToolInstallUI.cs
```
