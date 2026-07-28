<#
.SYNOPSIS
    Audits Claude Code documentation and configuration files.

.DESCRIPTION
    Scans .claude/ and ai/ directories for documentation files and reports sizes
    against TWO independent sets of limits:

      1. Claude Code PLATFORM limits (characters, skills/commands only) - hard
         constraints imposed by the tool itself: 20,000 warn / 30,000 error.

      2. PROJECT limits declared in ai/docs/documentation-maintenance.md - the
         "Commands and Skills: Reference, Don't Embed" architecture:
           - skills/commands: <2,000 good | 2,000-5,000 review | >5,000 refactor
           - the five core ai/*.md files: per-file line limits, <1,000 combined

    The project limits are far tighter than the platform limits. Reporting only
    the platform limits (this script's behavior before 2026-07-28) reported a
    clean bill of health while every large skill and command sat 2-4x over the
    project's own refactor threshold, and three core files were over their line
    limits. Both sets are now checked.

.PARAMETER Section
    Which section to audit: all, skills, commands, ai, docs, mcp
    Default: all

.PARAMETER WarningThreshold
    PLATFORM character threshold for warnings on skills/commands (default: 20000)

.PARAMETER ErrorThreshold
    PLATFORM character threshold for errors on skills/commands (default: 30000)

.PARAMETER RefactorThreshold
    PROJECT character threshold above which a skill/command must be refactored
    into ai/docs, keeping only a pointer (default: 5000)

.PARAMETER ReviewThreshold
    PROJECT character threshold above which a skill/command should be reviewed
    for extraction (default: 2000)

.EXAMPLE
    .\audit-docs.ps1
    Full audit of all sections

.EXAMPLE
    .\audit-docs.ps1 -Section skills
    Audit only skills

.EXAMPLE
    .\audit-docs.ps1 -Section mcp
    Audit only MCP documentation

.NOTES
    Exit code 1 when a HARD limit is breached: a platform ERROR (>=30,000 chars)
    or a core file over its declared line limit. REFACTOR and REVIEW are real
    debt and are reported prominently, but do not fail the run.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("all", "skills", "commands", "ai", "docs", "mcp")]
    [string]$Section = "all",
    [Parameter(Mandatory=$false)]
    [int]$WarningThreshold = 20000,
    [Parameter(Mandatory=$false)]
    [int]$ErrorThreshold = 30000,
    [Parameter(Mandatory=$false)]
    [int]$RefactorThreshold = 5000,
    [Parameter(Mandatory=$false)]
    [int]$ReviewThreshold = 2000
)

# Per-file line limits for the five core files, from
# ai/docs/documentation-maintenance.md ("The Five Core Files (NEVER exceed limits)").
# Files in ai/*.md not listed here (README.md, CLAUDE.md, TOC.md) are entry
# points or generated, and carry no declared limit.
$CoreFileLimits = @{
    "CRITICAL-RULES.md" = 100
    "MEMORY.md"         = 200
    "WORKFLOW.md"       = 200
    "STYLEGUIDE.md"     = 200
    "TESTING.md"        = 200
}
$CoreTotalLimit = 1000

# Determine repo root
$scriptPath = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptPath))
{
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)

function Measure-Lines
{
    # Counts lines the way `wc -l` does: a trailing newline terminates the last
    # line rather than starting an empty one. The previous naive split counted
    # one extra line on every newline-terminated file, which matters when the
    # number is compared against a hard limit.
    param([string]$Content)

    if ([string]::IsNullOrEmpty($Content)) { return 0 }

    $lines = $Content -split "`r?`n"
    if ($lines[-1] -eq '') { return $lines.Count - 1 }
    return $lines.Count
}

function Get-FileStats
{
    param(
        [string]$Path,
        [string]$Filter = "*.md",
        [switch]$Recurse
    )

    $files = if ($Recurse) {
        Get-ChildItem -Path $Path -Filter $Filter -Recurse -File -ErrorAction SilentlyContinue
    } else {
        Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction SilentlyContinue
    }

    $results = @()
    foreach ($file in $files)
    {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
        $charCount = if ($content) { $content.Length } else { 0 }

        $results += [PSCustomObject]@{
            Name = $file.Name
            RelativePath = $file.FullName.Substring($repoRoot.Length + 1)
            Characters = $charCount
            Lines = Measure-Lines -Content $content
        }
    }
    return $results
}

function Show-CharacterReport
{
    param(
        [string]$Title,
        [array]$Results,
        [int]$WarnAt,
        [int]$ErrorAt,
        [int]$RefactorAt,
        [int]$ReviewAt
    )

    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    Write-Host ("{0,-45} {1,12} {2,8} {3,10}" -f "File", "Characters", "Lines", "Status")
    Write-Host ("-" * 80)

    $sorted = $Results | Sort-Object -Property Characters -Descending
    $totalChars = 0
    $warnCount = 0
    $errCount = 0
    $refactorCount = 0
    $reviewCount = 0

    foreach ($item in $sorted)
    {
        $totalChars += $item.Characters
        $status = "OK"
        $color = "Green"

        if ($item.Characters -ge $ErrorAt)
        {
            $status = "ERROR"
            $color = "Red"
            $errCount++
        }
        elseif ($item.Characters -ge $WarnAt)
        {
            $status = "WARN"
            $color = "Yellow"
            $warnCount++
        }
        elseif ($item.Characters -ge $RefactorAt)
        {
            $status = "REFACTOR"
            $color = "Magenta"
            $refactorCount++
        }
        elseif ($item.Characters -ge $ReviewAt)
        {
            $status = "REVIEW"
            $color = "DarkYellow"
            $reviewCount++
        }

        $displayName = if ($item.Name.Length -gt 42) { $item.Name.Substring(0, 39) + "..." } else { $item.Name }
        Write-Host ("{0,-45} {1,12:N0} {2,8} {3,10}" -f $displayName, $item.Characters, $item.Lines, $status) -ForegroundColor $color
    }

    Write-Host ("-" * 80)
    Write-Host ("Total: {0} files, {1:N0} characters" -f $sorted.Count, $totalChars)
    if ($errCount -gt 0)      { Write-Host ("  ERROR (>={0:N0} chars, platform hard limit): {1}" -f $ErrorAt, $errCount) -ForegroundColor Red }
    if ($warnCount -gt 0)     { Write-Host ("  WARN (>={0:N0} chars, platform): {1}" -f $WarnAt, $warnCount) -ForegroundColor Yellow }
    if ($refactorCount -gt 0) { Write-Host ("  REFACTOR (>={0:N0} chars, project rule): {1} - move content to ai/docs/, keep a pointer" -f $RefactorAt, $refactorCount) -ForegroundColor Magenta }
    if ($reviewCount -gt 0)   { Write-Host ("  REVIEW (>={0:N0} chars, project rule): {1} - consider extracting to ai/docs/" -f $ReviewAt, $reviewCount) -ForegroundColor DarkYellow }

    return @{
        Total = $totalChars
        Count = $sorted.Count
        Warnings = $warnCount
        Errors = $errCount
        Refactor = $refactorCount
        Review = $reviewCount
    }
}

function Show-LineReport
{
    param(
        [string]$Title,
        [array]$Results,
        [hashtable]$Limits,
        [int]$TotalLimit = 0
    )

    $hasLimits = ($null -ne $Limits -and $Limits.Count -gt 0)

    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    if ($hasLimits)
    {
        Write-Host ("{0,-45} {1,8} {2,12} {3,8} {4,10}" -f "File", "Lines", "Characters", "Limit", "Status")
    }
    else
    {
        Write-Host ("{0,-55} {1,8} {2,12}" -f "File", "Lines", "Characters")
    }
    Write-Host ("-" * 80)

    $sorted = $Results | Sort-Object -Property Lines -Descending
    $totalLines = 0
    $totalChars = 0
    $violations = 0
    $limitedLines = 0

    foreach ($item in $sorted)
    {
        $totalLines += $item.Lines
        $totalChars += $item.Characters

        if ($hasLimits)
        {
            $limit = $Limits[$item.Name]
            $limitText = "-"
            $status = ""
            $color = "Gray"

            if ($null -ne $limit)
            {
                $limitedLines += $item.Lines
                $limitText = "$limit"
                if ($item.Lines -gt $limit)
                {
                    $status = "OVER +{0}" -f ($item.Lines - $limit)
                    $color = "Red"
                    $violations++
                }
                else
                {
                    $status = "OK"
                    $color = "Green"
                }
            }

            $displayName = if ($item.Name.Length -gt 42) { $item.Name.Substring(0, 39) + "..." } else { $item.Name }
            Write-Host ("{0,-45} {1,8} {2,12:N0} {3,8} {4,10}" -f $displayName, $item.Lines, $item.Characters, $limitText, $status) -ForegroundColor $color
        }
        else
        {
            $displayName = if ($item.Name.Length -gt 52) { $item.Name.Substring(0, 49) + "..." } else { $item.Name }
            Write-Host ("{0,-55} {1,8} {2,12:N0}" -f $displayName, $item.Lines, $item.Characters)
        }
    }

    Write-Host ("-" * 80)
    Write-Host ("Total: {0} files, {1:N0} lines, {2:N0} characters" -f $sorted.Count, $totalLines, $totalChars)

    $totalViolated = $false
    if ($hasLimits -and $TotalLimit -gt 0)
    {
        $totalStatus = if ($limitedLines -gt $TotalLimit) { "OVER by {0}" -f ($limitedLines - $TotalLimit) } else { "OK" }
        $totalColor = if ($limitedLines -gt $TotalLimit) { "Red" } else { "Green" }
        if ($limitedLines -gt $TotalLimit) { $totalViolated = $true }
        Write-Host ("Core files (limited subset): {0} of {1} lines - {2}" -f $limitedLines, $TotalLimit, $totalStatus) -ForegroundColor $totalColor
    }

    if ($violations -gt 0)
    {
        Write-Host ("  {0} core file(s) over the per-file limit declared in ai/docs/documentation-maintenance.md" -f $violations) -ForegroundColor Red
        Write-Host "  Fix: move detailed sections to the matching ai/docs/ guide, leave a pointer." -ForegroundColor Red
    }

    return @{
        TotalLines = $totalLines
        TotalChars = $totalChars
        Count = $sorted.Count
        CoreViolations = $violations
        CoreTotalViolated = $totalViolated
    }
}

# Header
Write-Host ""
Write-Host "Claude Code Documentation Audit" -ForegroundColor Cyan
Write-Host "Repository: $repoRoot"
Write-Host "Section: $Section"
Write-Host ""

$summary = @{}

# Skills audit
if ($Section -eq "all" -or $Section -eq "skills")
{
    $skillsPath = Join-Path $repoRoot ".claude\skills"
    if (Test-Path $skillsPath)
    {
        $skillFiles = Get-ChildItem -Path $skillsPath -Filter "SKILL.md" -Recurse -File -ErrorAction SilentlyContinue
        $skillResults = @()
        foreach ($file in $skillFiles)
        {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
            $charCount = if ($content) { $content.Length } else { 0 }
            $skillResults += [PSCustomObject]@{
                Name = $file.Directory.Name
                RelativePath = $file.FullName.Substring($repoRoot.Length + 1)
                Characters = $charCount
                Lines = Measure-Lines -Content $content
            }
        }
        $summary["skills"] = Show-CharacterReport -Title "Skills (.claude/skills/*/SKILL.md)" -Results $skillResults `
            -WarnAt $WarningThreshold -ErrorAt $ErrorThreshold -RefactorAt $RefactorThreshold -ReviewAt $ReviewThreshold
    }
}

# Commands audit
if ($Section -eq "all" -or $Section -eq "commands")
{
    $commandsPath = Join-Path $repoRoot ".claude\commands"
    if (Test-Path $commandsPath)
    {
        $commandResults = Get-FileStats -Path $commandsPath -Filter "*.md"
        $summary["commands"] = Show-CharacterReport -Title "Commands (.claude/commands/*.md)" -Results $commandResults `
            -WarnAt $WarningThreshold -ErrorAt $ErrorThreshold -RefactorAt $RefactorThreshold -ReviewAt $ReviewThreshold
    }
}

# ai/*.md audit (top-level only) - the five core files carry hard line limits
if ($Section -eq "all" -or $Section -eq "ai")
{
    $aiPath = Join-Path $repoRoot "ai"
    if (Test-Path $aiPath)
    {
        $aiResults = Get-FileStats -Path $aiPath -Filter "*.md"
        $summary["ai"] = Show-LineReport -Title "AI Root (ai/*.md)" -Results $aiResults `
            -Limits $CoreFileLimits -TotalLimit $CoreTotalLimit
    }
}

# ai/docs/*.md audit (top-level only) - explicitly unlimited, size is not a defect
if ($Section -eq "all" -or $Section -eq "docs")
{
    $docsPath = Join-Path $repoRoot "ai\docs"
    if (Test-Path $docsPath)
    {
        $docsResults = Get-FileStats -Path $docsPath -Filter "*.md"
        $summary["docs"] = Show-LineReport -Title "Documentation (ai/docs/*.md)" -Results $docsResults
    }
}

# ai/docs/mcp/*.md audit
if ($Section -eq "all" -or $Section -eq "mcp")
{
    $mcpPath = Join-Path $repoRoot "ai\docs\mcp"
    if (Test-Path $mcpPath)
    {
        $mcpResults = Get-FileStats -Path $mcpPath -Filter "*.md"
        $summary["mcp"] = Show-LineReport -Title "MCP Documentation (ai/docs/mcp/*.md)" -Results $mcpResults
    }
}

# Overall summary
if ($Section -eq "all")
{
    Write-Host ""
    Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
    Write-Host ""

    $totalErrors = 0
    $totalWarnings = 0
    $totalRefactor = 0
    $totalReview = 0
    $totalCoreViolations = 0
    $coreTotalViolated = $false

    foreach ($key in $summary.Keys)
    {
        $s = $summary[$key]
        if ($s.Errors)         { $totalErrors += $s.Errors }
        if ($s.Warnings)       { $totalWarnings += $s.Warnings }
        if ($s.Refactor)       { $totalRefactor += $s.Refactor }
        if ($s.Review)         { $totalReview += $s.Review }
        if ($s.CoreViolations) { $totalCoreViolations += $s.CoreViolations }
        if ($s.CoreTotalViolated) { $coreTotalViolated = $true }
    }

    $hardFailures = $totalErrors + $totalCoreViolations
    if ($coreTotalViolated) { $hardFailures++ }

    if ($hardFailures -eq 0 -and $totalWarnings -eq 0 -and $totalRefactor -eq 0 -and $totalReview -eq 0)
    {
        Write-Host "All documentation within platform AND project limits." -ForegroundColor Green
    }
    else
    {
        Write-Host "Platform limits (Claude Code hard constraints):" -ForegroundColor Cyan
        if ($totalErrors -gt 0)   { Write-Host "  Errors (>=$ErrorThreshold chars): $totalErrors" -ForegroundColor Red }
        if ($totalWarnings -gt 0) { Write-Host "  Warnings (>=$WarningThreshold chars): $totalWarnings" -ForegroundColor Yellow }
        if ($totalErrors -eq 0 -and $totalWarnings -eq 0) { Write-Host "  Clean" -ForegroundColor Green }

        Write-Host ""
        Write-Host "Project limits (ai/docs/documentation-maintenance.md):" -ForegroundColor Cyan
        if ($totalRefactor -gt 0)       { Write-Host "  Skills/commands needing REFACTOR (>=$RefactorThreshold chars): $totalRefactor" -ForegroundColor Magenta }
        if ($totalReview -gt 0)         { Write-Host "  Skills/commands to REVIEW (>=$ReviewThreshold chars): $totalReview" -ForegroundColor DarkYellow }
        if ($totalCoreViolations -gt 0) { Write-Host "  Core ai/*.md files over their line limit: $totalCoreViolations" -ForegroundColor Red }
        if ($coreTotalViolated)         { Write-Host "  Core files combined exceed $CoreTotalLimit lines" -ForegroundColor Red }
        if ($totalRefactor -eq 0 -and $totalReview -eq 0 -and $totalCoreViolations -eq 0 -and -not $coreTotalViolated) { Write-Host "  Clean" -ForegroundColor Green }

        if ($totalRefactor -gt 0 -or $totalReview -gt 0)
        {
            Write-Host ""
            Write-Host "Skills and commands are entry points, not encyclopedias. Move embedded" -ForegroundColor Gray
            Write-Host "knowledge into ai/docs/ and leave a pointer, so a non-Claude-Code LLM can" -ForegroundColor Gray
            Write-Host "be handed the ai/docs file and perform the task." -ForegroundColor Gray
        }
    }
}

Write-Host ""

# Exit code: non-zero only for HARD limit breaches - a platform error, or a core
# file (or the core total) over its declared line limit. REFACTOR/REVIEW are debt
# signals, reported above but deliberately not fatal.
$exitCode = 0
foreach ($key in $summary.Keys)
{
    if ($summary[$key].Errors -gt 0)         { $exitCode = 1 }
    if ($summary[$key].CoreViolations -gt 0) { $exitCode = 1 }
    if ($summary[$key].CoreTotalViolated)    { $exitCode = 1 }
}
exit $exitCode
