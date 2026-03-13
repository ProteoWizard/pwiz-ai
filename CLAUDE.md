# Claude Code Configuration for ProteoWizard/Skyline

This file contains critical information for Claude Code sessions working on this codebase.

## CRITICAL: Prefer `pwsh` for All Commands

### The Bash Tool Runs Git Bash — Not PowerShell

Claude Code's Bash tool uses **Git Bash** on Windows. Git Bash has limited access to
Windows tools and .NET global tools, and can silently swallow output from some commands.

**Route commands through `pwsh -Command` whenever possible:**

```bash
# Checking tool versions
pwsh -Command 'dotnet tool list -g'
pwsh -Command 'dottrace --version'

# Environment checks
pwsh -Command 'Get-ChildItem "$env:LOCALAPPDATA\JetBrains\Installations"'
pwsh -Command '$env:PATH -split ";" | Select-String dotnet'

# Running any .NET tool or Windows-native command
pwsh -Command 'dotCover --version'
pwsh -Command 'gh auth status'
```

**When Git Bash is fine:** Simple git commands (`git status`, `git diff`, `git log`),
basic file operations (`ls`, `mkdir`), and unix utilities work directly in Git Bash.

### Use `pwsh`, Never `powershell`

This project requires **PowerShell 7** (`pwsh`), not Windows PowerShell 5.1 (`powershell`).

```bash
# WRONG - Windows PowerShell 5.1
powershell -File .\script.ps1

# CORRECT - PowerShell 7 (scripts)
pwsh -File './path/to/script.ps1'

# CORRECT - PowerShell 7 (commands)
pwsh -Command 'Get-ChildItem "$env:LOCALAPPDATA\JetBrains"'
```

### CRITICAL: Script Path Syntax

The Bash tool in Claude Code does NOT correctly handle Windows-style paths with backslashes. Direct invocation fails:

```bash
# WRONG - Path gets mangled to ".aiscriptsSkylineBuild-Skyline.ps1"
.\ai\scripts\Skyline\Build-Skyline.ps1

# WRONG - Same problem with backslash paths
pwsh -File .\ai\scripts\Skyline\Build-Skyline.ps1
```

**Always use this pattern:**

```bash
# CORRECT - pwsh -File with forward slashes (no arguments)
pwsh -File './ai/scripts/Skyline/Build-Skyline.ps1'

# CORRECT - pwsh -File with arguments
pwsh -File './ai/scripts/Skyline/Build-Skyline.ps1' -RunTests -TestName CodeInspection

# CORRECT - Run-Tests.ps1 with arguments
pwsh -File './ai/scripts/Skyline/Run-Tests.ps1' -TestName TestPanoramaDownloadFile
```

### CRITICAL: Do NOT Use `&` (Call Operator)

**Never prefix script paths with `&` in pwsh commands.** The `&` breaks Claude Code's allowed tools permissions matching, causing commands that should be auto-approved to require manual approval.

```bash
# WRONG - & breaks permissions check
pwsh -Command "& './ai/scripts/Skyline/Build-Skyline.ps1'"

# CORRECT - use -File instead (supports arguments too)
pwsh -File './ai/scripts/Skyline/Build-Skyline.ps1'
pwsh -File './ai/scripts/Skyline/Run-Tests.ps1' -TestName SomeTest
```

### Why This Works

1. `pwsh -File` runs scripts directly and supports arguments after the script path
2. `pwsh -Command` is for inline PowerShell commands (not script files)
3. Forward slashes (`/`) work in PowerShell and don't get mangled by Git Bash
4. Using `-File` instead of `-Command "& ..."` avoids `&` which breaks permissions matching

## Common Build and Test Commands

```bash
# Full solution build
pwsh -File './ai/scripts/Skyline/Build-Skyline.ps1'

# Build with tests
pwsh -File './ai/scripts/Skyline/Build-Skyline.ps1' -RunTests

# Build specific target
pwsh -File './ai/scripts/Skyline/Build-Skyline.ps1' -Target TestConnected

# Run specific test
pwsh -File './ai/scripts/Skyline/Run-Tests.ps1' -TestName TestPanoramaDownloadFile

# Run test with internet access
pwsh -File './ai/scripts/Skyline/Run-Tests.ps1' -TestName TestPanoramaDownloadFile -Internet

# Run test with visible UI
pwsh -File './ai/scripts/Skyline/Run-Tests.ps1' -TestName TestSomeUITest -ShowUI
```

## CRITICAL: File Editing on Windows

### MANDATORY: Always Use Backslashes for File Paths in Edit Tools

**When using Edit or MultiEdit tools on Windows, you MUST use backslashes (`\`) in file paths, NOT forward slashes (`/`).**

```
# WRONG - Will cause errors (forward slashes)
Edit(file_path: "C:/YourProjectRoot/pwiz/pwiz_tools/Skyline/SomeFile.cs", ...)

# CORRECT - Always works (backslashes)
Edit(file_path: "C:\YourProjectRoot\pwiz\pwiz_tools\Skyline\SomeFile.cs", ...)
```

> **Note**: The paths above are illustrative. Replace `C:\YourProjectRoot` with your actual project root (e.g., `C:\Dev`, `D:\proj`, etc.).

This applies to:
- `Edit` tool
- `MultiEdit` tool
- `Write` tool
- `Read` tool

**Note**: This is the opposite of PowerShell script paths (which need forward slashes in the Bash tool). The distinction:
- **Bash tool with pwsh**: Use forward slashes in the quoted path string
- **Edit/Write/Read tools**: Use backslashes (Windows native paths)

## CRITICAL: Null Device on Windows

### NEVER redirect to `nul` in Git Bash

In Git Bash (used by the Bash tool), redirecting to `nul` creates an actual file instead of discarding output:

```bash
# WRONG - Creates a literal file named "nul" in the working directory
some_command > nul 2>&1

# CORRECT - Git Bash understands /dev/null
some_command > /dev/null 2>&1
```

For PowerShell commands:
```powershell
# CORRECT - PowerShell null handling
some_command | Out-Null
some_command > $null
```

**Why this matters**: The spurious `nul` file appears in `git status` as an untracked file and must be manually deleted.

## Documentation Discovery

**Unsure what documentation exists?** Consult **[ai/TOC.md](TOC.md)** - a comprehensive table of contents with:
- All 58 documents (core files, guides, skills, commands)
- One-line descriptions of each
- Size metrics (line/character counts)

This TOC is auto-generated by `ai/scripts/Generate-TOC.ps1` and updated during weekly syncs.

## Essential Documentation

Before writing code, read these files:

1. **ai/CRITICAL-RULES.md** - Absolute constraints (NO async/await, resource strings, etc.)
2. **ai/MEMORY.md** - Project context and gotchas
3. **ai/docs/build-and-test-guide.md** - Detailed build and test instructions

## Skills - Load Before Starting Work

**Load the appropriate skill BEFORE diving into work:**

- **skyline-development** → Any C# code changes, test writing, building, or codebase questions
- **version-control** → Before `git commit`, `git push`, `gh pr create`, or any git operations
- **debugging** → When investigating bugs, test failures, crashes, or "why is this happening?"
- **skyline-nightlytests** → For nightly test failures, handle/memory leaks, or test run queries
- **skyline-exceptions** → For exception reports, triage, or LabKey exception queries
- **tutorial-documentation** → For tutorial HTML, tutorial tests (TestTutorial/), or screenshots
- **skyline-screenshots** → For ImageComparer, screenshot diffs, or s-XX.png references
- **skyline-wiki** → For reading/updating wiki pages on skyline.ms
- **ai-context-documentation** → For ai/ folder docs, TODOs, or .claude/ files

## Debugging Behavior

**Recognize guess-and-test failure**: If you've made 3 attempts to fix a bug without understanding the root cause (hypothesis → change → test → fail cycle), STOP. Load the debugging skill and systematically isolate the problem before attempting another fix.

## Developer Environment

### Screenshots and Clipboard Images

Two tools for two sources:

- **"I took a screenshot"** → `mcp__status__get_last_screenshot()` — Win+Shift+S screenshots
- **"Check the clipboard"** → `mcp__status__get_clipboard_image()` — images copied from editors/browsers

Use `count` parameter to grab multiple screenshots at once (e.g., `count=3` for a series).
Read the returned path(s) with the Read tool to view the image(s).
