<#
.SYNOPSIS
    Verify developer environment for LLM-assisted Skyline development

.DESCRIPTION
    Checks all prerequisites from ai/docs/developer-setup-guide.md and outputs
    a summary report. Use this to quickly validate your workstation setup.

    Optional components can be explicitly skipped using the -Skip parameter.
    The script will pass if the only missing items are those explicitly skipped.

.PARAMETER Skip
    Array of optional component names to skip. Valid values:
    - netrc: Skip .netrc credentials check (LabKey API access)
    - labkey: Skip LabKey MCP Server registration check
    - teamcity: Skip TeamCity MCP Server registration check

.EXAMPLE
    .\Verify-Environment.ps1
    Run all environment checks and display status report

.EXAMPLE
    .\Verify-Environment.ps1 -Skip netrc
    Run checks but skip .netrc credentials (deferred for later setup)

.EXAMPLE
    .\Verify-Environment.ps1 -Skip netrc,labkey,teamcity
    Skip netrc, LabKey, and TeamCity MCP Server checks

.NOTES
    Author: LLM-assisted development
    See: ai/docs/developer-setup-guide.md

    MAINTENANCE: Keep this script in sync with ai/docs/developer-setup-guide.md.
    When prerequisites change in the documentation, update the checks here.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("netrc", "labkey", "teamcity")]
    [string[]]$Skip = @()
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent $scriptRoot  # pwiz-ai repo root

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Skyline Development Environment Check" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Track results for summary
$results = @()

function Add-Result {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details,
        [bool]$Success,
        [string]$SkipId = $null  # Optional ID for matching with -Skip parameter
    )
    $script:results += [PSCustomObject]@{
        Component = $Component
        Status = $Status
        Details = $Details
        Success = $Success
        SkipId = $SkipId
    }
}

function Test-Command {
    param([string]$Command)
    try {
        $null = & where.exe $Command 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

# ===========================================
# BOOTSTRAP PHASE (new-machine-bootstrap.md)
# ===========================================

# Git
Write-Host "Checking Git..." -ForegroundColor Gray
if (Test-Command "git") {
    try {
        $gitVersion = & git --version 2>$null
        if ($gitVersion -match '(\d+\.\d+\.\d+)') {
            Add-Result "Git" "OK" $Matches[1] $true
        } else {
            Add-Result "Git" "OK" $gitVersion $true
        }
    } catch {
        Add-Result "Git" "ERROR" "git found but version check failed" $false
    }
} else {
    Add-Result "Git" "MISSING" "Run: winget install Git.Git" $false
}

# Claude Code CLI
# NOTE: Do NOT run "claude update" here. When this script runs inside an active
# Claude Code session (via the Bash tool), "claude update" destroys all captured
# output from the entire process — even Write-Host calls that ran before it.
# This is a Claude Code bug discovered 2026-02-18. Just report the version.
Write-Host "Checking Claude Code CLI..." -ForegroundColor Gray
try {
    $claudeVersion = & claude --version 2>$null
    if ($claudeVersion -match '(\d+\.\d+\.\d+)') {
        Add-Result "Claude Code CLI" "OK" $Matches[1] $true
    } else {
        Add-Result "Claude Code CLI" "OK" $claudeVersion $true
    }
} catch {
    Add-Result "Claude Code CLI" "MISSING" "Run: npm install -g @anthropic-ai/claude-code" $false
}

# ===========================================
# REPOSITORY STRUCTURE (new-machine-setup.md)
# ===========================================

# Determine project root (parent of ai folder)
$projRoot = Split-Path -Parent $aiRoot

# .claude junction
Write-Host "Checking .claude junction..." -ForegroundColor Gray
$claudeJunctionPath = Join-Path $projRoot ".claude"
if (Test-Path $claudeJunctionPath) {
    $item = Get-Item $claudeJunctionPath -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $target = $item.Target
        if ($target -and ($target -replace '\\', '/') -match 'ai[/\\]claude$') {
            Add-Result ".claude junction" "OK" "points to ai\claude" $true
        } else {
            Add-Result ".claude junction" "WARN" "exists but may point to wrong target: $target" $false
        }
    } else {
        Add-Result ".claude junction" "WARN" "exists but is not a junction (is a regular folder)" $false
    }
} else {
    Add-Result ".claude junction" "MISSING" "Run: cmd /c mklink /J .claude ai\claude (from project root)" $false
}

# CLAUDE.md (hard link to ai/root-CLAUDE.md - one inode, two paths)
Write-Host "Checking CLAUDE.md..." -ForegroundColor Gray
$claudeMdPath = Join-Path $projRoot "CLAUDE.md"
$rootClaudeMdSource = Join-Path $aiRoot "root-CLAUDE.md"
if (Test-Path $rootClaudeMdSource) {
    # Detect hard-linkage by checking whether fsutil reports the source
    # path among the hard links of the target. fsutil prints volume-
    # relative paths (e.g. "\proj\ai\root-CLAUDE.md") so we normalize the
    # source to the same shape before comparing.
    $sourceVolRel = (Resolve-Path $rootClaudeMdSource).Path -replace '^[A-Za-z]:', ''
    $isLinked = $false
    if (Test-Path $claudeMdPath) {
        $links = & fsutil hardlink list $claudeMdPath 2>$null
        foreach ($link in $links) {
            if ($link.Trim() -eq $sourceVolRel) {
                $isLinked = $true
                break
            }
        }
    }

    if ($isLinked) {
        Add-Result "CLAUDE.md" "OK" "hard-linked to ai/root-CLAUDE.md" $true
    } else {
        # Legacy copy or missing - migrate to a hard link. (StatusMcp does
        # the same migration on every session start; doing it here covers
        # the pristine-machine setup flow before StatusMcp is registered.)
        if (Test-Path $claudeMdPath) {
            Remove-Item $claudeMdPath -Force
            $action = "re-linked from legacy copy"
        } else {
            $action = "created hard link"
        }
        & cmd /c mklink /H $claudeMdPath $rootClaudeMdSource | Out-Null
        if (Test-Path $claudeMdPath) {
            Add-Result "CLAUDE.md" "OK" $action $true
        } else {
            Add-Result "CLAUDE.md" "ERROR" "failed to create hard link (same volume required)" $false
        }
    }
} else {
    Add-Result "CLAUDE.md" "WARN" "ai/root-CLAUDE.md not found (git pull ai repo?)" $false
}

# settings.local.json
Write-Host "Checking Claude settings..." -ForegroundColor Gray
$settingsPath = Join-Path $aiRoot "claude\settings.local.json"
$defaultsPath = Join-Path $aiRoot "claude\settings-defaults.local.json"
if (Test-Path $settingsPath) {
    Add-Result "Claude settings.local.json" "OK" "configured" $true
} elseif (Test-Path $defaultsPath) {
    Add-Result "Claude settings.local.json" "MISSING" "Run: Copy-Item '$defaultsPath' '$settingsPath'" $false
} else {
    Add-Result "Claude settings.local.json" "MISSING" "create settings.local.json in ai\claude\" $false
}

# Discover git repositories in project root
Write-Host "Discovering git repositories..." -ForegroundColor Gray
$gitRepos = @()
$dirs = Get-ChildItem $projRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.claude' }
foreach ($dir in $dirs) {
    $gitDir = Join-Path $dir.FullName ".git"
    if (Test-Path $gitDir) {
        try {
            Push-Location $dir.FullName
            $branch = & git rev-parse --abbrev-ref HEAD 2>$null
            $remoteUrl = & git remote get-url origin 2>$null
            # Extract repo name from URL (e.g., "ProteoWizard/pwiz.git" -> "pwiz")
            $repoName = if ($remoteUrl -match '/([^/]+?)(\.git)?$') { $Matches[1] } else { "unknown" }
            $gitRepos += "$($dir.Name) -> $repoName ($branch)"
            Pop-Location
        } catch {
            $gitRepos += "$($dir.Name) -> (error reading git info)"
            if ((Get-Location).Path -ne $projRoot) { Pop-Location }
        }
    }
}

if ($gitRepos.Count -gt 0) {
    # Check if 'ai' is among the repos (required)
    $hasAi = $gitRepos | Where-Object { $_ -match '^ai ->' }
    if ($hasAi) {
        Add-Result "Git repositories" "OK" ($gitRepos -join "; ") $true
    } else {
        Add-Result "Git repositories" "WARN" "ai repo not found. Found: $($gitRepos -join '; ')" $false
    }
} else {
    Add-Result "Git repositories" "MISSING" "No git repositories found in $projRoot" $false
}

# ===========================================
# PREREQUISITES (new-machine-setup.md Phase 1)
# ===========================================

# Node.js
Write-Host "Checking Node.js..." -ForegroundColor Gray
if (Test-Command "node") {
    try {
        $nodeVersion = & node --version 2>$null
        if ($nodeVersion -match 'v?(\d+\.\d+\.\d+)') {
            $version = [version]$Matches[1]
            if ($version -ge [version]"18.0.0") {
                Add-Result "Node.js" "OK" $Matches[1] $true
            } else {
                Add-Result "Node.js" "WARN" "$($Matches[1]) (recommend 18+ LTS)" $false
            }
        } else {
            Add-Result "Node.js" "OK" $nodeVersion $true
        }
    } catch {
        Add-Result "Node.js" "ERROR" "node found but version check failed" $false
    }
} else {
    Add-Result "Node.js" "MISSING" "Run: winget install OpenJS.NodeJS.LTS" $false
}

# npm (comes with Node.js)
Write-Host "Checking npm..." -ForegroundColor Gray
if (Test-Command "npm") {
    try {
        $npmVersion = & npm --version 2>$null
        if ($npmVersion -match '(\d+\.\d+\.\d+)') {
            Add-Result "npm" "OK" $Matches[1] $true
        } else {
            Add-Result "npm" "OK" $npmVersion $true
        }
    } catch {
        Add-Result "npm" "ERROR" "npm found but version check failed" $false
    }
} else {
    Add-Result "npm" "MISSING" "Install Node.js: winget install OpenJS.NodeJS.LTS" $false
}

# PowerShell 7
Write-Host "Checking PowerShell..." -ForegroundColor Gray
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 7) {
    Add-Result "PowerShell 7" "OK" "$($psVersion.Major).$($psVersion.Minor).$($psVersion.Patch)" $true
} else {
    Add-Result "PowerShell 7" "WARN" "$($psVersion.Major).$($psVersion.Minor) (recommend 7+)" $false
}

# Python
Write-Host "Checking Python..." -ForegroundColor Gray
if (Test-Command "python") {
    try {
        $pythonVersion = & python --version 2>$null
        if ($pythonVersion -match '(\d+\.\d+\.\d+)') {
            $version = [version]$Matches[1]
            if ($version -ge [version]"3.10.0") {
                Add-Result "Python" "OK" $Matches[1] $true
            } else {
                Add-Result "Python" "WARN" "$($Matches[1]) (recommend 3.10+)" $false
            }
        } else {
            Add-Result "Python" "OK" $pythonVersion $true
        }
    } catch {
        Add-Result "Python" "ERROR" "python found but version check failed" $false
    }
} else {
    Add-Result "Python" "MISSING" "Install Python 3.10+" $false
}

# Git configuration
Write-Host "Checking Git configuration..." -ForegroundColor Gray
try {
    $autocrlf = & git config core.autocrlf 2>$null
    if ($autocrlf -eq "true") {
        Add-Result "Git core.autocrlf" "OK" "true" $true
    } elseif ($autocrlf) {
        Add-Result "Git core.autocrlf" "WARN" "$autocrlf (recommend: true)" $false
    } else {
        Add-Result "Git core.autocrlf" "MISSING" "Run: git config --global core.autocrlf true" $false
    }
} catch {
    Add-Result "Git core.autocrlf" "ERROR" "Could not check git config" $false
}

try {
    $pullRebase = & git config pull.rebase 2>$null
    if ($pullRebase -eq "false") {
        Add-Result "Git pull.rebase" "OK" "false (merge)" $true
    } elseif ($pullRebase -eq "true") {
        Add-Result "Git pull.rebase" "INFO" "true (rebase) - consider 'false' for safer merges" $true
    } elseif ($pullRebase) {
        Add-Result "Git pull.rebase" "INFO" "$pullRebase" $true
    } else {
        Add-Result "Git pull.rebase" "INFO" "not set (defaults to merge)" $true
    }
} catch {
    Add-Result "Git pull.rebase" "ERROR" "Could not check git config" $false
}

# 4. Visual Studio
Write-Host "Checking Visual Studio..." -ForegroundColor Gray
$vsVersions = @()
$vs2022Path = "C:\Program Files\Microsoft Visual Studio\2022"
$vs2026Path = "C:\Program Files\Microsoft Visual Studio\18"
if (Test-Path $vs2022Path) {
    $editions = Get-ChildItem $vs2022Path -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    foreach ($edition in $editions) {
        $vsVersions += "2022 $edition"
    }
}
if (Test-Path $vs2026Path) {
    $editions = Get-ChildItem $vs2026Path -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    foreach ($edition in $editions) {
        $vsVersions += "2026 $edition"
    }
}
if ($vsVersions.Count -gt 0) {
    Add-Result "Visual Studio" "OK" ($vsVersions -join ", ") $true
} else {
    Add-Result "Visual Studio" "MISSING" "Install from visualstudio.microsoft.com" $false
}

# 5. TortoiseGit
Write-Host "Checking TortoiseGit..." -ForegroundColor Gray
$tortoiseGitPath = "C:\Program Files\TortoiseGit\bin\TortoiseGitProc.exe"
if (Test-Path $tortoiseGitPath) {
    # Try to get version from file properties
    try {
        $version = (Get-Item $tortoiseGitPath).VersionInfo.ProductVersion
        if ($version) {
            Add-Result "TortoiseGit" "OK" $version $true
        } else {
            Add-Result "TortoiseGit" "OK" "installed" $true
        }
    } catch {
        Add-Result "TortoiseGit" "OK" "installed" $true
    }
} else {
    Add-Result "TortoiseGit" "MISSING" "Run: winget install TortoiseGit.TortoiseGit" $false
}

# Notepad++ (optional utility)
Write-Host "Checking Notepad++..." -ForegroundColor Gray
$notepadPlusPath = "C:\Program Files\Notepad++\notepad++.exe"
if (Test-Path $notepadPlusPath) {
    try {
        $version = (Get-Item $notepadPlusPath).VersionInfo.ProductVersion
        if ($version) {
            Add-Result "Notepad++" "OK" $version $true
        } else {
            Add-Result "Notepad++" "OK" "installed" $true
        }
    } catch {
        Add-Result "Notepad++" "OK" "installed" $true
    }
} else {
    Add-Result "Notepad++" "INFO" "optional - Run: winget install Notepad++.Notepad++" $true
}

# ReSharper CLI (jb inspectcode)
Write-Host "Checking ReSharper CLI tools..." -ForegroundColor Gray
if (Test-Command "jb") {
    try {
        $jbOutput = & jb inspectcode --version 2>&1 | Out-String
        if ($jbOutput -match 'Inspect Code (\d+\.\d+\.\d+)') {
            Add-Result "ReSharper CLI (jb)" "OK" $Matches[1] $true
        } elseif ($jbOutput -match 'Version:\s*(\d+\.\d+\.\d+)') {
            Add-Result "ReSharper CLI (jb)" "OK" $Matches[1] $true
        } else {
            Add-Result "ReSharper CLI (jb)" "OK" "installed" $true
        }
    } catch {
        Add-Result "ReSharper CLI (jb)" "ERROR" "jb found but inspectcode failed" $false
    }
} else {
    Add-Result "ReSharper CLI (jb)" "MISSING" "Run: dotnet tool install -g JetBrains.ReSharper.GlobalTools" $false
}

# 5. dotCover CLI
Write-Host "Checking dotCover CLI..." -ForegroundColor Gray
if (Test-Command "dotCover") {
    try {
        $dotCoverOutput = & dotCover --version 2>&1 | Out-String
        # Match "dotCover Console Runner X.Y.Z" pattern
        if ($dotCoverOutput -match 'dotCover.*?(\d{4}\.\d+\.\d+)') {
            $version = $Matches[1]
            # Check for known buggy versions
            if ($version -match '^2025\.3\.' -or [version]$version -gt [version]"2025.2.99") {
                Add-Result "dotCover CLI" "WARN" "$version (2025.3.0+ has JSON export bug, use 2025.1.7)" $false
            } else {
                Add-Result "dotCover CLI" "OK" $version $true
            }
        } else {
            Add-Result "dotCover CLI" "OK" "installed" $true
        }
    } catch {
        Add-Result "dotCover CLI" "ERROR" "dotCover found but version check failed" $false
    }
} else {
    Add-Result "dotCover CLI" "MISSING" "Run: dotnet tool install --global JetBrains.dotCover.CommandLineTools --version 2025.1.7" $false
}

# dotMemory CLI (optional - for memory profiling)
Write-Host "Checking dotMemory CLI..." -ForegroundColor Gray
$dotMemoryPath = $null
$dotMemoryBase = Join-Path $env:USERPROFILE ".claude-tools\dotMemory"
if (Test-Path $dotMemoryBase) {
    # Find dotMemory.exe in version subfolder (e.g., ~/.claude-tools/dotMemory/2025.3.1/tools/dotMemory.exe)
    $versionDirs = Get-ChildItem $dotMemoryBase -Directory -ErrorAction SilentlyContinue
    foreach ($versionDir in $versionDirs) {
        $testPath = Join-Path $versionDir.FullName "tools\dotMemory.exe"
        if (Test-Path $testPath) {
            $dotMemoryPath = $testPath
            break
        }
    }
}
if ($dotMemoryPath) {
    try {
        # Parse version from command output: "dotMemory Console Profiler 2025.3.1 build ..."
        $output = & $dotMemoryPath help 2>&1 | Select-Object -First 1
        if ($output -match 'dotMemory.*?(\d{4}\.\d+\.\d+)') {
            Add-Result "dotMemory CLI" "OK" $Matches[1] $true
        } else {
            Add-Result "dotMemory CLI" "OK" "installed" $true
        }
    } catch {
        Add-Result "dotMemory CLI" "OK" "installed" $true
    }
} else {
    Add-Result "dotMemory CLI" "INFO" "optional - Run: pwsh -File ai/scripts/Install-DotMemory.ps1" $true
}

# 9. dotTrace CLI (optional - for performance profiling)
Write-Host "Checking dotTrace CLI..." -ForegroundColor Gray
if (Test-Command "dottrace") {
    try {
        $dotTraceOutput = & dottrace --version 2>&1 | Out-String
        if ($dotTraceOutput -match '(\d+\.\d+\.\d+)') {
            Add-Result "dotTrace CLI" "OK" $Matches[1] $true
        } else {
            Add-Result "dotTrace CLI" "OK" "installed" $true
        }
    } catch {
        Add-Result "dotTrace CLI" "ERROR" "dottrace found but version check failed" $false
    }
} else {
    Add-Result "dotTrace CLI" "INFO" "optional - Run: dotnet tool install --global JetBrains.dotTrace.GlobalTools" $true
}

# dotTrace Reporter.exe (optional - for automated XML reports)
Write-Host "Checking dotTrace Reporter.exe..." -ForegroundColor Gray
$reporterPath = $null
$dotTraceInstalls = Get-ChildItem "$env:LOCALAPPDATA\JetBrains\Installations" -Directory -Filter "dotTrace*" -ErrorAction SilentlyContinue
foreach ($install in $dotTraceInstalls) {
    $testPath = Join-Path $install.FullName "Reporter.exe"
    if (Test-Path $testPath) {
        $reporterPath = $testPath
        break
    }
}
if ($reporterPath) {
    try {
        # Parse version from command output: "dotTrace Reporter 2025.3.1 build ..."
        $output = & $reporterPath 2>&1 | Select-Object -First 1
        if ($output -match 'dotTrace Reporter (\d{4}\.\d+\.\d+)') {
            Add-Result "dotTrace Reporter" "OK" $Matches[1] $true
        } else {
            Add-Result "dotTrace Reporter" "OK" "installed" $true
        }
    } catch {
        Add-Result "dotTrace Reporter" "OK" "installed" $true
    }
} else {
    Add-Result "dotTrace Reporter" "INFO" "optional - requires dotTrace GUI (JetBrains)" $true
}

# 11. GitHub CLI
Write-Host "Checking GitHub CLI..." -ForegroundColor Gray
if (Test-Command "gh") {
    try {
        $ghOutput = & gh --version 2>$null | Select-Object -First 1
        if ($ghOutput -match '(\d+\.\d+\.\d+)') {
            Add-Result "GitHub CLI (gh)" "OK" $Matches[1] $true
        } else {
            Add-Result "GitHub CLI (gh)" "OK" "installed" $true
        }
    } catch {
        Add-Result "GitHub CLI (gh)" "ERROR" "gh found but version check failed" $false
    }
} else {
    Add-Result "GitHub CLI (gh)" "MISSING" "Run: winget install GitHub.cli" $false
}

# 7. GitHub CLI Authentication
Write-Host "Checking GitHub CLI authentication..." -ForegroundColor Gray
if (Test-Command "gh") {
    try {
        $authStatus = & gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Add-Result "GitHub CLI Auth" "OK" "authenticated" $true
        } else {
            Add-Result "GitHub CLI Auth" "MISSING" "Run: gh auth login (in interactive terminal)" $false
        }
    } catch {
        Add-Result "GitHub CLI Auth" "MISSING" "Run: gh auth login (in interactive terminal)" $false
    }
} else {
    Add-Result "GitHub CLI Auth" "SKIP" "gh not installed" $false
}

# Python MCP packages
Write-Host "Checking Python MCP packages..." -ForegroundColor Gray
$labkeyInstalled = $false
$mcpInstalled = $false
$pillowInstalled = $false
try {
    $pipShow = & pip show labkey mcp Pillow 2>&1
    if ($pipShow -match 'Name: labkey') { $labkeyInstalled = $true }
    if ($pipShow -match 'Name: mcp') { $mcpInstalled = $true }
    if ($pipShow -match 'Name: Pillow') { $pillowInstalled = $true }
} catch {}
# Fallback: try python -m pip, then search common Python locations
# (handles cases where pip isn't in PATH, or python is the Microsoft Store stub)
if (-not ($labkeyInstalled -and $mcpInstalled -and $pillowInstalled)) {
    $pythonCandidates = @('python')
    # Search common Windows Python installation paths
    $pythonDirs = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*",
        "C:\Python3*",
        "$env:ProgramFiles\Python3*"
    )
    foreach ($pattern in $pythonDirs) {
        $found = Get-ChildItem $pattern -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        foreach ($dir in $found) {
            $candidate = Join-Path $dir.FullName "python.exe"
            if (Test-Path $candidate) { $pythonCandidates += $candidate }
        }
    }
    foreach ($py in $pythonCandidates) {
        if ($labkeyInstalled -and $mcpInstalled -and $pillowInstalled) { break }
        try {
            $pipShow = & $py -m pip show labkey mcp Pillow 2>&1
            if ($pipShow -match 'Name: labkey') { $labkeyInstalled = $true }
            if ($pipShow -match 'Name: mcp') { $mcpInstalled = $true }
            if ($pipShow -match 'Name: Pillow') { $pillowInstalled = $true }
        } catch {}
    }
}

if ($labkeyInstalled -and $mcpInstalled -and $pillowInstalled) {
    Add-Result "Python packages (labkey, mcp, Pillow)" "OK" "installed" $true
} elseif ($labkeyInstalled -or $mcpInstalled -or $pillowInstalled) {
    $missing = @()
    if (-not $labkeyInstalled) { $missing += "labkey" }
    if (-not $mcpInstalled) { $missing += "mcp" }
    if (-not $pillowInstalled) { $missing += "Pillow" }
    Add-Result "Python packages" "PARTIAL" "Missing: $($missing -join ', '). Run: pip install $($missing -join ' ')" $false
} else {
    Add-Result "Python packages (labkey, mcp, Pillow)" "MISSING" "Run: pip install mcp labkey Pillow" $false
}

# 10. netrc file for LabKey
Write-Host "Checking netrc credentials..." -ForegroundColor Gray
$netrcPath = Join-Path $env:USERPROFILE ".netrc"
$netrcAltPath = Join-Path $env:USERPROFILE "_netrc"
$hasNetrc = (Test-Path $netrcPath) -or (Test-Path $netrcAltPath)
if ($hasNetrc) {
    $foundPath = if (Test-Path $netrcPath) { ".netrc" } else { "_netrc" }
    Add-Result "netrc credentials" "OK" "$foundPath exists" $true -SkipId "netrc"
} elseif ($Skip -contains "netrc") {
    Add-Result "netrc credentials" "SKIPPED" "Deferred (use -Skip netrc to acknowledge)" $true -SkipId "netrc"
} else {
    Add-Result "netrc credentials" "MISSING" "Needs a +claude account on skyline.ms (see new-machine-setup.md, search for +claude)" $false -SkipId "netrc"
}

# 11. LabKey MCP Server registration
Write-Host "Checking LabKey MCP server..." -ForegroundColor Gray
if ($Skip -contains "labkey") {
    Add-Result "LabKey MCP Server" "SKIPPED" "Deferred (use -Skip labkey to acknowledge)" $true -SkipId "labkey"
} else {
    # NOTE: Do NOT call "claude mcp list" or any "claude" subcommand here.
    # When this script runs inside an active Claude Code session (via the Bash tool),
    # any "claude" subcommand destroys all captured output from the entire process.
    # Instead, read the MCP config directly from ~/.claude.json.
    try {
        $serverPath = Join-Path $aiRoot "mcp\LabKeyMcp\server.py"
        $serverExists = Test-Path $serverPath

        # Read MCP server config from ~/.claude.json
        $claudeJsonPath = Join-Path $env:USERPROFILE ".claude.json"
        $isRegistered = $false
        $isDisabled = $false
        $registeredArgs = $null

        if (Test-Path $claudeJsonPath) {
            $claudeConfig = Get-Content $claudeJsonPath -Raw | ConvertFrom-Json
            # Normalize project root to forward-slash for comparison
            $projKeyBase = ($projRoot -replace '\\', '/').TrimEnd('/')

            # Search all project entries under this workspace root (handles the case where
            # MCP servers were registered from a subdirectory, e.g. pwiz1/, rather than
            # the workspace root itself)
            foreach ($key in $claudeConfig.projects.PSObject.Properties.Name) {
                $normalizedKey = ($key -replace '\\', '/').TrimEnd('/')
                if ($normalizedKey -eq $projKeyBase -or $normalizedKey.StartsWith($projKeyBase + '/')) {
                    $pc = $claudeConfig.projects.$key
                    if ($pc.mcpServers.labkey -and -not $isRegistered) {
                        $isRegistered = $true
                        $registeredArgs = $pc.mcpServers.labkey.args -join ' '
                        $projectConfig = $pc  # expose for TeamCity check below
                    }
                    if ($pc.disabledMcpServers -contains 'labkey') {
                        $isDisabled = $true
                    }
                }
            }
        }

        if ($isRegistered -and -not $isDisabled -and $hasNetrc) {
            Add-Result "LabKey MCP Server" "OK" "registered ($registeredArgs)" $true -SkipId "labkey"
        } elseif ($isRegistered -and $isDisabled) {
            Add-Result "LabKey MCP Server" "WARN" "registered but disabled (enable via /mcp in Claude Code)" $false -SkipId "labkey"
        } elseif ($isRegistered -and -not $hasNetrc) {
            Add-Result "LabKey MCP Server" "WARN" "registered but ~\.netrc missing - API calls will fail" $false -SkipId "labkey"
        } elseif ($serverExists) {
            Add-Result "LabKey MCP Server" "MISSING" "Run: claude mcp add labkey -- python $serverPath" $false -SkipId "labkey"
        } else {
            Add-Result "LabKey MCP Server" "ERROR" "server.py not found at $serverPath" $false -SkipId "labkey"
        }
    } catch {
        Add-Result "LabKey MCP Server" "ERROR" "Could not check MCP status: $_" $false -SkipId "labkey"
    }
}

# 12. TeamCity MCP Server registration (optional)
Write-Host "Checking TeamCity MCP server..." -ForegroundColor Gray
if ($Skip -contains "teamcity") {
    Add-Result "TeamCity MCP Server" "SKIPPED" "Deferred (use -Skip teamcity to acknowledge)" $true -SkipId "teamcity"
} else {
    try {
        $tcServerPath = Join-Path $aiRoot "mcp\TeamCityMcp\server.py"
        $tcServerExists = Test-Path $tcServerPath
        $tcConfigPath = Join-Path $env:USERPROFILE ".teamcity-mcp\config.json"
        $hasTcConfig = Test-Path $tcConfigPath

        # Check MCP registration in ~/.claude.json (same scan-all-subdirs pattern as LabKey check)
        $tcRegistered = $false
        $tcDisabled = $false
        if (Test-Path $claudeJsonPath) {
            if (-not $claudeConfig) {
                $claudeConfig = Get-Content $claudeJsonPath -Raw | ConvertFrom-Json
            }
            $projKeyBase = ($projRoot -replace '\\', '/').TrimEnd('/')
            foreach ($key in $claudeConfig.projects.PSObject.Properties.Name) {
                $normalizedKey = ($key -replace '\\', '/').TrimEnd('/')
                if ($normalizedKey -eq $projKeyBase -or $normalizedKey.StartsWith($projKeyBase + '/')) {
                    $pc = $claudeConfig.projects.$key
                    if ($pc.mcpServers.teamcity) { $tcRegistered = $true }
                    if ($pc.disabledMcpServers -contains 'teamcity') { $tcDisabled = $true }
                }
            }
        }

        if ($tcRegistered -and -not $tcDisabled -and $hasTcConfig) {
            Add-Result "TeamCity MCP Server" "OK" "registered with config" $true -SkipId "teamcity"
        } elseif ($tcRegistered -and $tcDisabled) {
            Add-Result "TeamCity MCP Server" "WARN" "registered but disabled" $false -SkipId "teamcity"
        } elseif ($tcRegistered -and -not $hasTcConfig) {
            Add-Result "TeamCity MCP Server" "WARN" "registered but ~\.teamcity-mcp\config.json missing" $false -SkipId "teamcity"
        } elseif ($tcServerExists -and -not $tcRegistered) {
            Add-Result "TeamCity MCP Server" "MISSING" "See ai/docs/mcp/setup.md#teamcity-mcp" $false -SkipId "teamcity"
        } else {
            Add-Result "TeamCity MCP Server" "MISSING" "Optional - see ai/docs/mcp/setup.md#teamcity-mcp" $false -SkipId "teamcity"
        }
    } catch {
        Add-Result "TeamCity MCP Server" "ERROR" "Could not check: $_" $false -SkipId "teamcity"
    }
}

# ===========================================
# LSP CODE INTELLIGENCE (new-machine-setup.md Phase 7.6)
# ===========================================
# C# checks are INFO-level (optional) for now - promote to MISSING once
# the team decides Roslyn LSP is required.
#
# Rust checks (rustup, rust-analyzer, rust-analyzer-lsp plugin) are NICHE -
# only relevant for the shrinking population still working on the maccoss/osprey
# Rust implementation. Do NOT offer Rust setup proactively. Surface the rows so
# someone who IS doing Rust work sees missing pieces, but the "INFO - skip
# unless you work on maccoss/osprey" wording should keep an LLM assistant from
# trying to install Rust on every machine.

# VS Code (required only for the C# extension that bundles Roslyn LSP)
Write-Host "Checking VS Code..." -ForegroundColor Gray
if (Test-Command "code") {
    try {
        $codeVersion = & code --version 2>$null | Select-Object -First 1
        if ($codeVersion -match '(\d+\.\d+\.\d+)') {
            Add-Result "VS Code" "OK" $Matches[1] $true
        } else {
            Add-Result "VS Code" "OK" "installed" $true
        }
    } catch {
        Add-Result "VS Code" "INFO" "optional - Run: winget install Microsoft.VisualStudioCode" $true
    }
} else {
    Add-Result "VS Code" "INFO" "optional (needed for C# LSP) - Run: winget install Microsoft.VisualStudioCode" $true
}

# VS Code C# extension (ships Microsoft.CodeAnalysis.LanguageServer)
Write-Host "Checking VS Code C# extension (Roslyn LSP host)..." -ForegroundColor Gray
$vscodeExtRoot = Join-Path $env:USERPROFILE ".vscode\extensions"
$csharpExtDir = $null
$roslynServerExe = $null
if (Test-Path $vscodeExtRoot) {
    $csharpExtDir = Get-ChildItem $vscodeExtRoot -Directory -Filter 'ms-dotnettools.csharp-*' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1
    if ($csharpExtDir) {
        $roslynServerExe = Join-Path $csharpExtDir.FullName ".roslyn\Microsoft.CodeAnalysis.LanguageServer.exe"
    }
}
if ($csharpExtDir -and (Test-Path $roslynServerExe)) {
    # Extract version (e.g., "ms-dotnettools.csharp-2.130.5-win32-x64" -> "2.130.5")
    if ($csharpExtDir.Name -match 'ms-dotnettools\.csharp-(\d+\.\d+\.\d+)') {
        Add-Result "VS Code C# extension (Roslyn LSP)" "OK" $Matches[1] $true
    } else {
        Add-Result "VS Code C# extension (Roslyn LSP)" "OK" "installed" $true
    }
} elseif ($csharpExtDir) {
    Add-Result "VS Code C# extension (Roslyn LSP)" "WARN" "extension found but Roslyn server missing at $roslynServerExe - reinstall the extension" $false
} else {
    Add-Result "VS Code C# extension (Roslyn LSP)" "INFO" "optional (needed for C# LSP) - Run: code --install-extension ms-dotnettools.csharp" $true
}

# Claude Code plugin cache reflects install state. Marketplace dir presence ==
# user ran "/plugin marketplace add". Plugin subdir presence == "/plugin install".
$pluginCacheRoot = Join-Path $env:USERPROFILE ".claude\plugins\cache"

# pwiz-lsp marketplace registered
Write-Host "Checking pwiz-lsp marketplace registration..." -ForegroundColor Gray
$pwizLspCache = Join-Path $pluginCacheRoot "pwiz-lsp"
if (Test-Path $pwizLspCache) {
    Add-Result "pwiz-lsp marketplace" "OK" "registered" $true
} else {
    Add-Result "pwiz-lsp marketplace" "INFO" "optional - In Claude Code: /plugin marketplace add C:/proj/ai/claude/plugins/pwiz-lsp" $true
}

# csharp-lsp@pwiz-lsp installed. Claude Code keeps old version dirs in the cache
# when /plugin marketplace update bumps a plugin, so sort by version number (not
# LastWriteTime) to report the highest installed version.
Write-Host "Checking csharp-lsp@pwiz-lsp plugin..." -ForegroundColor Gray
$csharpLspCache = Join-Path $pwizLspCache "csharp-lsp"
if (Test-Path $csharpLspCache) {
    $versionDirs = Get-ChildItem $csharpLspCache -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^\d+\.\d+\.\d+' }
    $highest = $versionDirs | Sort-Object { [version]($_.Name -replace '^(\d+\.\d+\.\d+).*', '$1') } -Descending |
               Select-Object -First 1
    if ($highest) {
        $extra = if ($versionDirs.Count -gt 1) { " ($($versionDirs.Count) versions cached)" } else { "" }
        Add-Result "csharp-lsp@pwiz-lsp plugin" "OK" "v$($highest.Name)$extra" $true
    } else {
        Add-Result "csharp-lsp@pwiz-lsp plugin" "OK" "installed" $true
    }
} else {
    Add-Result "csharp-lsp@pwiz-lsp plugin" "INFO" "optional - In Claude Code: /plugin install csharp-lsp@pwiz-lsp then /reload-plugins" $true
}

# --- Rust LSP path (only relevant for maccoss/osprey work) ---
# These three checks are grouped at the end of the LSP section because they
# apply to a shrinking minority of developers. The "skip unless..." wording
# in the INFO message tells an LLM assistant not to proactively offer setup.

# rustup toolchain
Write-Host "Checking rustup (Rust toolchain)..." -ForegroundColor Gray
if (Test-Command "rustup") {
    try {
        $rustupVersion = & rustup --version 2>$null | Select-Object -First 1
        if ($rustupVersion -match 'rustup\s+(\d+\.\d+\.\d+)') {
            Add-Result "rustup" "OK" $Matches[1] $true
        } else {
            Add-Result "rustup" "OK" "installed" $true
        }
    } catch {
        Add-Result "rustup" "ERROR" "rustup found but version check failed" $false
    }
} else {
    Add-Result "rustup" "INFO" "skip unless working on maccoss/osprey - Run: winget install Rustlang.Rustup" $true
}

# rust-analyzer component
Write-Host "Checking rust-analyzer component..." -ForegroundColor Gray
if (Test-Command "rustup") {
    try {
        $raCheck = & rust-analyzer --version 2>&1 | Out-String
        if ($raCheck -match 'rust-analyzer\s+(\S+)') {
            Add-Result "rust-analyzer (LSP)" "OK" $Matches[1] $true
        } else {
            Add-Result "rust-analyzer (LSP)" "INFO" "skip unless working on maccoss/osprey - Run: rustup component add rust-analyzer" $true
        }
    } catch {
        Add-Result "rust-analyzer (LSP)" "INFO" "skip unless working on maccoss/osprey - Run: rustup component add rust-analyzer" $true
    }
} else {
    Add-Result "rust-analyzer (LSP)" "INFO" "skip unless working on maccoss/osprey - install rustup first" $true
}

# rust-analyzer-lsp@claude-plugins-official installed
Write-Host "Checking rust-analyzer-lsp@claude-plugins-official plugin..." -ForegroundColor Gray
$raPluginCache = Join-Path $pluginCacheRoot "claude-plugins-official\rust-analyzer-lsp"
if (Test-Path $raPluginCache) {
    Add-Result "rust-analyzer-lsp plugin" "OK" "installed" $true
} else {
    Add-Result "rust-analyzer-lsp plugin" "INFO" "skip unless working on maccoss/osprey - In Claude Code: /plugin install rust-analyzer-lsp@claude-plugins-official" $true
}

# Leftover old-marketplace cache from previous "maccoss-lsp" naming
Write-Host "Checking for leftover plugin caches..." -ForegroundColor Gray
$staleMaccossCache = Join-Path $pluginCacheRoot "maccoss-lsp"
if (Test-Path $staleMaccossCache) {
    Add-Result "Leftover maccoss-lsp cache" "WARN" "delete with: Remove-Item -Recurse -Force '$staleMaccossCache'" $false
} else {
    Add-Result "Leftover plugin caches" "OK" "none" $true
}

# Print Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Environment Check Results" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$maxComponentLen = ($results | ForEach-Object { $_.Component.Length } | Measure-Object -Maximum).Maximum
$maxStatusLen = 7  # "MISSING" is longest

foreach ($result in $results) {
    $component = $result.Component.PadRight($maxComponentLen)
    $statusColor = switch ($result.Status) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "PARTIAL" { "Yellow" }
        "INFO" { "Cyan" }
        "SKIP" { "Gray" }
        "SKIPPED" { "Magenta" }
        default { "Red" }
    }
    $statusText = "[$($result.Status)]".PadRight($maxStatusLen + 2)

    Write-Host "  $component " -NoNewline
    Write-Host $statusText -ForegroundColor $statusColor -NoNewline
    Write-Host " $($result.Details)"
}

# Summary counts
$okCount = ($results | Where-Object { $_.Status -eq "OK" }).Count
$warnCount = ($results | Where-Object { $_.Status -in @("WARN", "PARTIAL") }).Count
$missingCount = ($results | Where-Object { $_.Status -eq "MISSING" }).Count
$errorCount = ($results | Where-Object { $_.Status -eq "ERROR" }).Count
$skippedCount = ($results | Where-Object { $_.Status -eq "SKIPPED" }).Count

Write-Host "`n----------------------------------------" -ForegroundColor Gray
if ($skippedCount -gt 0) {
    Write-Host "  OK: $okCount | Warnings: $warnCount | Skipped: $skippedCount | Missing: $missingCount | Errors: $errorCount" -ForegroundColor Gray
} else {
    Write-Host "  OK: $okCount | Warnings: $warnCount | Missing: $missingCount | Errors: $errorCount" -ForegroundColor Gray
}

# Show which items were skipped
if ($Skip.Count -gt 0) {
    Write-Host "  Explicitly skipped: $($Skip -join ', ')" -ForegroundColor Magenta
}

if ($missingCount -eq 0 -and $errorCount -eq 0 -and $warnCount -eq 0) {
    if ($skippedCount -gt 0) {
        Write-Host "`n[PASS] Environment configured (with $skippedCount deferred item(s): $($Skip -join ', '))" -ForegroundColor Green
    } else {
        Write-Host "`n[PASS] Environment is fully configured for LLM-assisted development" -ForegroundColor Green
    }
    exit 0
} elseif ($missingCount -eq 0 -and $errorCount -eq 0) {
    if ($skippedCount -gt 0) {
        Write-Host "`n[PASS] Environment ready with warnings (deferred: $($Skip -join ', '))" -ForegroundColor Yellow
    } else {
        Write-Host "`n[PASS] Environment is ready (some optional items have warnings)" -ForegroundColor Yellow
    }
    exit 0
} else {
    Write-Host "`n[FAIL] Some components need configuration" -ForegroundColor Red
    Write-Host "See: ai/docs/developer-setup-guide.md for installation instructions" -ForegroundColor Gray
    if ($missingCount -gt 0) {
        $missingItems = $results | Where-Object { $_.Status -eq "MISSING" } | ForEach-Object { $_.Component }
        Write-Host "Missing: $($missingItems -join ', ')" -ForegroundColor Gray
    }
    Write-Host ""
    exit ($missingCount + $errorCount)
}
