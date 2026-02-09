<#
.SYNOPSIS
    Verify developer environment for LabKey Server development

.DESCRIPTION
    Checks all prerequisites for LabKey development and outputs a summary report.
    Run this to quickly validate your workstation setup before starting installation.

.PARAMETER LabKeyVersion
    Target LabKey version: "25" for LabKey 25.x (Java 17) or "26" for LabKey 26.x (Java 25)

    Note: Within LabKey 25.x, PostgreSQL support varies:
    - LabKey 25.7.x and lower: PostgreSQL 17 only
    - LabKey 25.11.x: PostgreSQL 17 or 18

.EXAMPLE
    .\Verify-LabKeyEnvironment.ps1 -LabKeyVersion 25
    Check environment for LabKey 25.x development (Java 17, PostgreSQL 17 recommended)

.EXAMPLE
    .\Verify-LabKeyEnvironment.ps1 -LabKeyVersion 26
    Check environment for LabKey 26.x development (Java 25, PostgreSQL 18)
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("25", "26")]
    [string]$LabKeyVersion
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Determine required versions based on LabKey version
$requiredJavaVersion = if ($LabKeyVersion -eq "25") { 17 } else { 25 }
$recommendedPgVersion = if ($LabKeyVersion -eq "25") { 17 } else { 18 }

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "LabKey Development Environment Check" -ForegroundColor Cyan
Write-Host "Target: LabKey $LabKeyVersion.x (Java $requiredJavaVersion)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Track results for summary
$results = @()

function Add-Result {
    param(
        [string]$Component,
        [string]$Status,
        [string]$Details,
        [bool]$Required = $true
    )
    $script:results += [PSCustomObject]@{
        Component = $Component
        Status = $Status
        Details = $Details
        Required = $Required
    }
}

function Test-Command {
    param([string]$Command)
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# 1. Console Encoding
Write-Host "Checking console encoding..." -ForegroundColor Gray
$encoding = [Console]::OutputEncoding
if ($encoding.CodePage -eq 65001) {
    Add-Result "Console Encoding" "OK" "UTF-8 (CP65001)" -Required $false
} else {
    Add-Result "Console Encoding" "WARN" "$($encoding.EncodingName) (CP$($encoding.CodePage)) - recommend UTF-8 for international characters" -Required $false
}

# 2. Git
Write-Host "Checking Git..." -ForegroundColor Gray
if (Test-Command "git") {
    $gitVersionRaw = (git --version) -replace 'git version ', ''
    # Extract just the version number (e.g., "2.43.0" from "2.43.0.windows.1")
    $gitVersion = if ($gitVersionRaw -match '^(\d+\.\d+\.\d+)') { $Matches[1] } else { $gitVersionRaw }

    # Check latest version from winget
    $wingetInfo = winget show Git.Git --source winget 2>&1 | Out-String
    $latestVersion = $null
    if ($wingetInfo -match "Version:\s*(\d+\.\d+\.\d+)") {
        $latestVersion = $Matches[1]
    }

    if ($latestVersion -and ([version]$latestVersion -gt [version]$gitVersion)) {
        Add-Result "Git" "UPDATE" "$gitVersion → $latestVersion available: winget upgrade Git.Git --source winget"
    } else {
        Add-Result "Git" "OK" "$gitVersion (latest)"
    }
} else {
    Add-Result "Git" "MISSING" "Run: winget install Git.Git --source winget"
}

# 3. Git core.autocrlf
Write-Host "Checking Git autocrlf..." -ForegroundColor Gray
if (Test-Command "git") {
    $autocrlf = git config core.autocrlf 2>$null
    if ($autocrlf -eq "true") {
        Add-Result "Git core.autocrlf" "OK" "true"
    } else {
        Add-Result "Git core.autocrlf" "MISSING" "Run: git config --global core.autocrlf true"
    }
} else {
    Add-Result "Git core.autocrlf" "SKIP" "Git not installed"
}

# 4. SSH Key
Write-Host "Checking SSH key..." -ForegroundColor Gray
$sshKeyPath = Join-Path $env:USERPROFILE ".ssh\id_ed25519.pub"
$sshKeyPathRsa = Join-Path $env:USERPROFILE ".ssh\id_rsa.pub"
if ((Test-Path $sshKeyPath) -or (Test-Path $sshKeyPathRsa)) {
    $keyType = if (Test-Path $sshKeyPath) { "ed25519" } else { "rsa" }
    Add-Result "SSH Key" "OK" "$keyType key found"
} else {
    Add-Result "SSH Key" "MISSING" "Run: ssh-keygen -t ed25519 -C 'your-email@example.com'"
}

# 5. GitHub SSH Access
Write-Host "Checking GitHub SSH access..." -ForegroundColor Gray
if (Test-Command "ssh") {
    $sshTest = ssh -T git@github.com 2>&1
    if ($sshTest -match "successfully authenticated") {
        Add-Result "GitHub SSH" "OK" "authenticated"
    } else {
        Add-Result "GitHub SSH" "MISSING" "Add SSH key to GitHub: https://github.com/settings/keys"
    }
} else {
    Add-Result "GitHub SSH" "SKIP" "SSH not available"
}

# 6. Java
Write-Host "Checking Java..." -ForegroundColor Gray
$javaHome = [System.Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
if ($javaHome -and (Test-Path "$javaHome\bin\java.exe")) {
    $javaVersionOutput = & "$javaHome\bin\java.exe" -version 2>&1
    $javaVersionLine = $javaVersionOutput | Select-Object -First 1
    if ($javaVersionLine -match '"?(\d+)[\._]') {
        $majorVersion = [int]$Matches[1]
        if ($majorVersion -eq $requiredJavaVersion) {
            Add-Result "Java $requiredJavaVersion" "OK" $javaVersionLine
        } else {
            Add-Result "Java $requiredJavaVersion" "WRONG" "Found Java $majorVersion - need Java $requiredJavaVersion for LabKey $LabKeyVersion.x"
        }
    } else {
        Add-Result "Java $requiredJavaVersion" "WARN" "Could not parse version: $javaVersionLine"
    }
} elseif ($javaHome) {
    Add-Result "Java $requiredJavaVersion" "MISSING" "JAVA_HOME set but java.exe not found at $javaHome"
} else {
    Add-Result "Java $requiredJavaVersion" "MISSING" "Run: winget install EclipseAdoptium.Temurin.$requiredJavaVersion.JDK --source winget --interactive"
}

# 7. JAVA_HOME
Write-Host "Checking JAVA_HOME..." -ForegroundColor Gray
if ($javaHome) {
    Add-Result "JAVA_HOME" "OK" $javaHome
} else {
    Add-Result "JAVA_HOME" "MISSING" "Set during JDK installation (enable 'Set JAVA_HOME variable')"
}

# 8. PostgreSQL
Write-Host "Checking PostgreSQL..." -ForegroundColor Gray
$pgService = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pgService) {
    $pgVersion = $pgService.Name -replace 'postgresql-x64-', '' -replace 'postgresql-', ''
    $pgMajorVersion = [int]($pgVersion -replace '\..*', '')

    if ($pgService.Status -eq 'Running') {
        # Check version compatibility
        if ($LabKeyVersion -eq "25") {
            if ($pgMajorVersion -eq 17) {
                Add-Result "PostgreSQL" "OK" "v$pgVersion (running) - compatible with all LabKey 25.x"
            } elseif ($pgMajorVersion -eq 18) {
                Add-Result "PostgreSQL" "OK" "v$pgVersion (running) - compatible with LabKey 25.11.x+ only (not 25.7.x and lower)"
            } else {
                Add-Result "PostgreSQL" "WARN" "v$pgVersion (running) - LabKey 25.x recommends PostgreSQL 17 or 18"
            }
        } elseif ($LabKeyVersion -eq "26") {
            if ($pgMajorVersion -eq 18) {
                Add-Result "PostgreSQL" "OK" "v$pgVersion (running)"
            } else {
                Add-Result "PostgreSQL" "WARN" "v$pgVersion (running) - LabKey 26.x requires PostgreSQL 18"
            }
        } else {
            Add-Result "PostgreSQL" "OK" "v$pgVersion (running)"
        }
    } else {
        Add-Result "PostgreSQL" "WARN" "v$pgVersion (not running) - Start service: Start-Service $($pgService.Name)"
    }
} else {
    if ($LabKeyVersion -eq "25") {
        Add-Result "PostgreSQL" "MISSING" "Run: winget install PostgreSQL.PostgreSQL.17 --source winget --interactive (recommended for all 25.x)"
    } else {
        Add-Result "PostgreSQL" "MISSING" "Run: winget install PostgreSQL.PostgreSQL.$recommendedPgVersion --source winget --interactive"
    }
}

# 9. IntelliJ IDEA
Write-Host "Checking IntelliJ IDEA..." -ForegroundColor Gray
$intellijPaths = @(
    "C:\Program Files\JetBrains\IntelliJ IDEA Community*",
    "C:\Program Files\JetBrains\IntelliJ IDEA 20*",
    "C:\Program Files\JetBrains\IntelliJ IDEA Ultimate*"
)
$intellijFound = $null
foreach ($pattern in $intellijPaths) {
    $found = Get-Item $pattern -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($found) {
        $intellijFound = $found
        break
    }
}
if ($intellijFound) {
    $edition = if ($intellijFound.Name -match "Community") { "Community" } elseif ($intellijFound.Name -match "Ultimate") { "Ultimate" } else { "Unknown" }
    $version = if ($intellijFound.Name -match '(\d{4}\.\d+)') { $Matches[1] } else { "Unknown" }
    Add-Result "IntelliJ IDEA" "OK" "$edition $version"
} else {
    Add-Result "IntelliJ IDEA" "MISSING" "Run: winget install JetBrains.IntelliJIDEA.Community --source winget"
}

# 10. GitHub CLI (optional - for Claude Code)
Write-Host "Checking GitHub CLI..." -ForegroundColor Gray
if (Test-Command "gh") {
    $ghVersion = (gh --version | Select-Object -First 1) -replace 'gh version ', ''
    # Check auth status
    $authStatus = gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Add-Result "GitHub CLI" "OK" "v$ghVersion (authenticated)" -Required $false
    } else {
        Add-Result "GitHub CLI" "WARN" "v$ghVersion (not authenticated) - Run: gh auth login" -Required $false
    }
} else {
    Add-Result "GitHub CLI" "MISSING" "Run: winget install GitHub.cli --source winget (optional, for Claude Code)" -Required $false
}

# 11. Claude Code (optional)
Write-Host "Checking Claude Code..." -ForegroundColor Gray
if (Test-Command "claude") {
    $claudeVersion = claude --version 2>$null
    Add-Result "Claude Code" "OK" $claudeVersion -Required $false
} else {
    Add-Result "Claude Code" "MISSING" "Run: irm https://claude.ai/install.ps1 | iex (optional)" -Required $false
}

# 12. Notepad++ (optional)
Write-Host "Checking Notepad++..." -ForegroundColor Gray
if (Test-Path 'C:\Program Files\Notepad++\notepad++.exe') {
    $nppVersion = (Get-Item 'C:\Program Files\Notepad++\notepad++.exe').VersionInfo.ProductVersion
    Add-Result "Notepad++" "OK" "v$nppVersion" -Required $false
} else {
    Add-Result "Notepad++" "MISSING" "Run: winget install Notepad++.Notepad++ --source winget" -Required $false
}

# 13. WinMerge (optional)
Write-Host "Checking WinMerge..." -ForegroundColor Gray
$winmergePath = if (Test-Path 'C:\Program Files\WinMerge\WinMergeU.exe') {
    'C:\Program Files\WinMerge\WinMergeU.exe'
} elseif (Test-Path "$env:LOCALAPPDATA\Programs\WinMerge\WinMergeU.exe") {
    "$env:LOCALAPPDATA\Programs\WinMerge\WinMergeU.exe"
} else {
    $null
}
if ($winmergePath) {
    $wmVersion = (Get-Item $winmergePath).VersionInfo.ProductVersion
    Add-Result "WinMerge" "OK" "v$wmVersion" -Required $false
} else {
    Add-Result "WinMerge" "MISSING" "Run: winget install WinMerge.WinMerge --source winget" -Required $false
}

# 14. TortoiseGit (optional)
Write-Host "Checking TortoiseGit..." -ForegroundColor Gray
if (Test-Path 'C:\Program Files\TortoiseGit\bin\TortoiseGitProc.exe') {
    $tgVersion = (Get-Item 'C:\Program Files\TortoiseGit\bin\TortoiseGitProc.exe').VersionInfo.ProductVersion
    Add-Result "TortoiseGit" "OK" "v$tgVersion" -Required $false
} else {
    Add-Result "TortoiseGit" "MISSING" "Run: winget install TortoiseGit.TortoiseGit --source winget" -Required $false
}

# Print Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Environment Check Results" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$maxComponentLen = ($results | ForEach-Object { $_.Component.Length } | Measure-Object -Maximum).Maximum

foreach ($result in $results) {
    $component = $result.Component.PadRight($maxComponentLen)
    $statusColor = switch ($result.Status) {
        "OK" { "Green" }
        "UPDATE" { "Cyan" }
        "INFO" { "Cyan" }
        "WARN" { "Yellow" }
        "WRONG" { "Red" }
        "SKIP" { "Gray" }
        default { "Red" }
    }
    $requiredMarker = if ($result.Required) { "" } else { " (optional)" }

    Write-Host "  $component " -NoNewline
    Write-Host "[$($result.Status)]".PadRight(9) -ForegroundColor $statusColor -NoNewline
    Write-Host " $($result.Details)$requiredMarker"
}

# Summary counts
$requiredResults = $results | Where-Object { $_.Required }
$okCount = ($requiredResults | Where-Object { $_.Status -in @("OK", "UPDATE") }).Count
$missingCount = ($requiredResults | Where-Object { $_.Status -in @("MISSING", "WRONG") }).Count
$warnCount = ($requiredResults | Where-Object { $_.Status -eq "WARN" }).Count
$updateCount = ($requiredResults | Where-Object { $_.Status -eq "UPDATE" }).Count
$totalRequired = $requiredResults.Count

Write-Host "`n----------------------------------------" -ForegroundColor Gray
if ($updateCount -gt 0) {
    Write-Host "  Required: $okCount/$totalRequired OK | Updates available: $updateCount | Warnings: $warnCount | Missing: $missingCount" -ForegroundColor Gray
} else {
    Write-Host "  Required: $okCount/$totalRequired OK | Warnings: $warnCount | Missing: $missingCount" -ForegroundColor Gray
}

if ($missingCount -eq 0) {
    Write-Host "`n[READY] Environment is configured for LabKey $LabKeyVersion.x development" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[SETUP NEEDED] $missingCount required component(s) need to be installed" -ForegroundColor Yellow
    $missingItems = $requiredResults | Where-Object { $_.Status -in @("MISSING", "WRONG") } | ForEach-Object { $_.Component }
    Write-Host "Missing: $($missingItems -join ', ')" -ForegroundColor Gray
    exit $missingCount
}
