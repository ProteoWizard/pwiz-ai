# Project-Wide Utility Scripts

This directory contains PowerShell scripts for maintaining code quality, automating workflows, and supporting LLM-assisted development across the ProteoWizard project.

## Script Index

### Code Quality

| Script | Description |
|--------|-------------|
| `fix-crlf.ps1` | Convert modified files from LF to CRLF (Windows standard) |
| `validate-bom-compliance.ps1` | Validate no unexpected UTF-8 BOMs in repository |
| `analyze-bom-git.ps1` | Audit git-tracked files for UTF-8 BOMs |
| `remove-bom.ps1` | Remove UTF-8 BOMs from specified files |
| `revert-whitespace-only-files.ps1` | Revert files with only whitespace changes (e.g., tab-to-space in RESX) |

### Auditing

| Script | Description |
|--------|-------------|
| `audit-docs.ps1` | Audit documentation file sizes (line/character counts) |
| `audit-loc.ps1` | Audit lines of code using cloc, categorized by path and type |
| `audit-skills.ps1` | Audit skill sizes to ensure <30K character limit |
| `audit-skyline-testdata.ps1` | Audit test data file sizes to identify large files |

### Documentation & TOC

| Script | Description |
|--------|-------------|
| `Generate-TOC.ps1` | Generate `ai/TOC.md` — comprehensive table of contents with size metrics |

### TODO & Report Management

| Script | Description |
|--------|-------------|
| `Archive-CompletedTodos.ps1` | Archive old completed TODOs into year/month subfolders |
| `Clean-TmpFiles.ps1` | Clean stale transient files from `ai/.tmp/` |
| `Move-DailyReports.ps1` | Move daily report files into per-date folders under `ai/.tmp/daily/` |
| `Invoke-DailyReport.ps1` | Run Claude Code daily report in non-interactive mode |

### Environment & Setup

| Script | Description |
|--------|-------------|
| `Verify-Environment.ps1` | Verify developer environment prerequisites |
| `Install-DotMemory.ps1` | Install JetBrains dotMemory Console CLI tool |
| `statusline.ps1` | Custom Claude Code status line (project, branch, model, context %) |

### Analysis

| Script | Description |
|--------|-------------|
| `analyze-http-json.ps1` | Analyze HTTP recording JSON files for request sizes |
| `Get-DiskUsage.ps1` | True disk use per folder when runs share files through hard links (Osprey run directories): unique size, and what deleting each folder would actually free |

### Skyline/ — Build & Test

| Script | Description |
|--------|-------------|
| `Skyline/Build-Skyline.ps1` | Build, test, and validate Skyline from LLM-assisted IDEs |
| `Skyline/Run-Tests.ps1` | Test execution wrapper with locale support and SkylineTester integration |
| `Skyline/scripts/Analyze-Coverage.ps1` | Analyze dotCover JSON results for code coverage |
| `Skyline/scripts/Extract-TypeNames.ps1` | Extract namespace/type names from C# files for coverage |
| `Skyline/scripts/Sync-DotSettings.ps1` | Synchronize ReSharper .DotSettings across solutions |

See [Skyline/README.md](Skyline/README.md) for detailed Skyline build/test documentation.

### Translation/ - ja / zh-Hans localization

Validation of ResourcesOrganizer CSVs plus the corpus, glossary, drafting, reviewer-package and
evaluation scripts from the first Claude-drafted translation round. See
[Translation/README.md](Translation/README.md).

### CarafeSharp/

| Script | Description |
|--------|-------------|
| `CarafeSharp/Build-CarafeSharp.ps1` | Build and test `pwiz_tools/CarafeSharp` (wraps its `build.ps1`), with ReSharper inspection |
| `CarafeSharp/Run-CarafeSharpWorkflow.ps1` | The CarafeSharp/Osprey workflow: library, search, fine-tune, search |
| `CarafeSharp/New-CarafeSharpTestData.ps1` | Build the test data package zips listed in `testdata.json` |
| `CarafeSharp/SubsetData/*.py` | Cut the committed test data subsets (`CarafeSharp.Test/TestData/*.zip`); see its README |
| `CarafeSharp/Measure-CumulativeCoverage.ps1` | dotCover coverage of the unit tests plus `regression.ps1`, merged |
| `CarafeSharp/Audit-Loc.ps1` | cloc audit of CarafeSharp against its Carafe (Java + Python) reference |

### BiblioSpec/

| Script | Description |
|--------|-------------|
| `BiblioSpec/Build-BiblioSpec.ps1` | Build and test the BiblioSpec C# port (`pwiz_tools/BiblioSpec`); `-RunTests` runs its 142 reference checks, which also gate an edit to the shared `BiblioSpec.IO` writer or schema |

### AutoQC/ and SkylineBatch/

| Script | Description |
|--------|-------------|
| `AutoQC/Build-AutoQC.ps1` | Build and test AutoQC.sln |
| `SkylineBatch/Build-SkylineBatch.ps1` | Build and test SkylineBatch.sln |

## Common Workflows

### Before Committing LLM-Generated Code

```powershell
pwsh -File './ai/scripts/fix-crlf.ps1'                 # Fix line endings
pwsh -File './ai/scripts/validate-bom-compliance.ps1'   # Check BOMs
```

### If BOM Validation Fails

```powershell
pwsh -File './ai/scripts/remove-bom.ps1' -Execute
```

### Regenerate Documentation TOC

```powershell
pwsh -File './ai/scripts/Generate-TOC.ps1'
```

## UTF-8 Output for PowerShell Scripts

LLM-authored PowerShell scripts often emit Unicode status icons. Add this guard near the top of every such script:

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

## Background

### Why CRLF (Windows line endings)?

The ProteoWizard project is primarily developed on Windows with Windows-native build tools. Consistent CRLF avoids spurious diffs when LLM tools convert to LF. **Exception:** Shell scripts (`.sh`) and Jamfiles use LF per `.editorconfig`.

### Why UTF-8 without BOM?

UTF-8 BOMs are unnecessary and can cause build failures, parser errors, and version control noise. **Approved exceptions:** Visual Studio COM type library files (`.tli`, `.tlh`) and Agilent vendor data files.

## Related Documentation

- **[ai/STYLEGUIDE.md](../STYLEGUIDE.md)** - File headers, encoding guidelines
- **[ai/WORKFLOW.md](../WORKFLOW.md)** - Git workflow, commit practices
- **[ai/docs/build-and-test-guide.md](../docs/build-and-test-guide.md)** - Build/test automation
