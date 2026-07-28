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

    Beyond sizes, -Section checks runs CONTENT verifiers. Per CRITICAL-RULES.md,
    "a rule without a verifier drifts" - each exists because a rule was written
    down, followed for a while, then quietly stopped being followed:
      - pwsh -Command "& ..." instead of -File (breaks permission matching)
      - relative links that do not resolve
      - /pw-* references naming a command that does not exist
      - ai/docs linking into ai/claude/skills (pointers run docs <- skills)
      - phrases banned by C:\proj\CLAUDE.md ("Language and Tone")

.PARAMETER Section
    Which section to audit: all, skills, commands, ai, docs, mcp, checks
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
    Exit code 1 when a HARD limit is breached: a platform ERROR (>=30,000 chars),
    a core file over its declared line limit, or any content-check violation.
    REFACTOR and REVIEW are real debt and are reported prominently, but do not
    fail the run - 16 files sit in that state today, and a script that always
    exits 1 gets ignored.

    todos/ and docs/archive/ are excluded from content checks: both are frozen
    records, and "fixing" them would falsify history.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("all", "skills", "commands", "ai", "docs", "mcp", "checks")]
    [string]$Section = "all",
    [Parameter(Mandatory=$false)]
    [int]$WarningThreshold = 20000,
    [Parameter(Mandatory=$false)]
    [int]$ErrorThreshold = 30000,
    [Parameter(Mandatory=$false)]
    [int]$RefactorThreshold = 5000,
    [Parameter(Mandatory=$false)]
    [int]$ReviewThreshold = 2000,
    # How many example violations to list per content check. The default keeps the
    # report readable; raise it when you are actually working through the list.
    [Parameter(Mandatory=$false)]
    [int]$MaxDetail = 6
)

# Per-file line limits from ai/docs/documentation-maintenance.md.
#
# The five core files ALSO share a combined <1000-line budget. CLAUDE.md carries
# its own per-file limit but is deliberately NOT part of that budget: it is a
# Claude Code platform file, not one of the five, and folding it into the sum
# would silently raise the bar the five are measured against.
#
# TOC.md (generated), root-CLAUDE.md (mirror of the project-root file) and
# README.md (navigation entry point) are exempt by design - see
# documentation-maintenance.md, "The rest of ai/ root".
$CoreFileLimits = @{
    "CRITICAL-RULES.md" = 100
    "MEMORY.md"         = 200
    "WORKFLOW.md"       = 200
    "STYLEGUIDE.md"     = 200
    "TESTING.md"        = 200
}
$CoreTotalLimit = 1000

# Checked per-file, excluded from the $CoreTotalLimit budget above.
$PlatformFileLimits = @{
    "CLAUDE.md" = 250
}

# Files that legitimately CONTAIN a prohibited pattern because they DEFINE the
# prohibition - their WRONG examples are the documentation. Without this, every
# content check below fires on the rule that created it, and a check that cries
# wolf on its own source gets muted.
$RuleDefiningFiles = @(
    "CLAUDE.md"                     # shows `pwsh -Command "& ..."` as the WRONG example
    "root-CLAUDE.md"                # mirror of the project-root CLAUDE.md; defines the banned phrases
    "TOC.md"                        # generated index; legitimately links every skill
    "audit-docs.ps1"                # this file - $BannedPhrases below spells them out
    "documentation-maintenance.md"  # governing design doc; quotes the patterns it forbids
    "pw-auditdocs.md"               # documents these very checks, including their WRONG forms
)

# Phrases banned by C:\proj\CLAUDE.md ("Language and Tone").
$BannedPhrases = @(
    @{ Pattern = 'load-bearing'; Guidance = 'use "critical" / "key", or "essential" when the point is it cannot be removed' }
    @{ Pattern = 'smoking gun';  Guidance = 'use "root cause" / "found the mismatch" - we are engineers, not crime-scene investigators' }
)

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
        [int]$TotalLimit = 0,
        [string[]]$BudgetFiles = @()
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
                # Only files named in -BudgetFiles count toward the combined
                # budget; other limited files (CLAUDE.md) are per-file only.
                if ($BudgetFiles -contains $item.Name) { $limitedLines += $item.Lines }
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

function Test-CorpusRules
{
    <#
      Content checks, as opposed to the size checks above. Per CRITICAL-RULES.md,
      "a rule without a verifier drifts" - each check here exists because a rule
      was written down, followed for a while, and then quietly stopped being
      followed because nothing measured it.

      Every check honours $RuleDefiningFiles: the document that DEFINES a
      prohibition necessarily contains the prohibited pattern as its WRONG
      example, and a checker that fires on its own source gets muted.
    #>
    param(
        [string]$AiRoot,
        [string[]]$RuleDefiningFiles,
        [array]$BannedPhrases,
        [int]$MaxDetail = 6
    )

    Write-Host ""
    Write-Host "=== Content Checks ===" -ForegroundColor Cyan
    Write-Host "Rules from ai/docs/documentation-maintenance.md, ai/CLAUDE.md, C:\proj\CLAUDE.md"
    Write-Host ("-" * 80)

    # todos/ and docs/archive/ are frozen records, not live documentation. A TODO
    # describes what was true when it was written; an archived doc is kept
    # precisely because it is superseded. "Fixing" their links would falsify the
    # record, and leaving them failing forever is how a check gets muted.
    $skipDirs = '[\\/](\.git|\.tmp|node_modules|todos)[\\/]'
    $allFiles = @(
        Get-ChildItem -Path $AiRoot -Include *.md, *.ps1 -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch $skipDirs -and $_.FullName -notmatch '[\\/]docs[\\/]archive[\\/]' }
    )

    $findings = @()
    $commandsDir = Join-Path $AiRoot "claude\commands"

    foreach ($file in $allFiles)
    {
        $rel = $file.FullName.Substring($AiRoot.Length + 1)
        $isRuleDef = $RuleDefiningFiles -contains $file.Name
        $isMarkdown = $file.Extension -eq ".md"
        $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)
        $inFence = $false

        for ($i = 0; $i -lt $lines.Count; $i++)
        {
            $line = $lines[$i]
            $lineNo = $i + 1

            # Track fenced code blocks. LINK checks skip them: a fence in a guide is
            # illustrative markdown ("See [docs/topic.md](docs/topic.md)" showing what
            # a pointer should look like from ai/ root), and resolving it from the
            # containing file's directory is meaningless. The call-operator, /pw-* and
            # banned-phrase checks deliberately still apply inside fences - a wrong
            # pwsh invocation in a ```powershell block is exactly what we are hunting.
            if ($line -match '^\s*```') { $inFence = -not $inFence }

            # --- Check 1: the `&` call operator breaks Claude Code permission matching
            if (-not $isRuleDef -and $line -match '-Command\s+"\s*&')
            {
                $findings += [PSCustomObject]@{ Check = "call-operator"; File = $rel; Line = $lineNo
                    Detail = 'pwsh -Command "& ..." breaks permissions matching - use -File' }
            }

            # --- Check 5: banned phrases (C:\proj\CLAUDE.md, "Language and Tone")
            if (-not $isRuleDef)
            {
                foreach ($banned in $BannedPhrases)
                {
                    if ($line -imatch [regex]::Escape($banned.Pattern))
                    {
                        $findings += [PSCustomObject]@{ Check = "banned-phrase"; File = $rel; Line = $lineNo
                            Detail = "'$($banned.Pattern)' - $($banned.Guidance)" }
                    }
                }
            }

            # --- Check 3: every /pw-* token names a command that exists
            # A slash command appears at a token boundary (start of line, after
            # whitespace, backtick, quote or paren). The lookbehind stops the same
            # pattern matching INSIDE a path - ".claude/commands/pw-daily-$P.md"
            # contains "/pw-daily-" but is a filename, not a command reference.
            # Requiring an alphanumeric last char rejects the interpolation stub.
            foreach ($m in [regex]::Matches($line, '(?<![\w./-])/pw-[a-z0-9-]*[a-z0-9]'))
            {
                $cmdName = $m.Value.TrimStart('/')
                if (-not (Test-Path -LiteralPath (Join-Path $commandsDir "$cmdName.md")))
                {
                    $findings += [PSCustomObject]@{ Check = "dangling-command"; File = $rel; Line = $lineNo
                        Detail = "$($m.Value) has no claude/commands/$cmdName.md" }
                }
            }

            if (-not $isMarkdown -or $inFence) { continue }

            foreach ($m in [regex]::Matches($line, '\]\(([^)]+)\)'))
            {
                $target = $m.Groups[1].Value.Trim()

                # --- Check 4: ai/docs must not link into ai/claude/skills
                if ($rel -like "docs\*" -and -not $isRuleDef -and $target -match 'claude[\\/]skills[\\/].+SKILL\.md')
                {
                    $findings += [PSCustomObject]@{ Check = "docs-to-skill"; File = $rel; Line = $lineNo
                        Detail = "links into a skill ($target) - skills point at docs, not the reverse" }
                }

                # --- Check 2: relative links resolve
                if ($target -match '^(https?:|mailto:|#)') { continue }
                $path = ($target -replace '#.*$', '').Trim()
                if ([string]::IsNullOrWhiteSpace($path)) { continue }
                $path = [uri]::UnescapeDataString($path)
                if ($path -match '^[a-zA-Z]:' -or $path.StartsWith('/')) { continue }  # absolute: not ours to resolve

                # Template placeholders in fill-in-the-blank forms, e.g.
                # "**Issue**: [#NNN](url)" in pw-handoff.md. These are meant to be
                # replaced by the author, not followed.
                if ($path -match '^(url|link|path|filename|file)$' -or
                    $path -match '[<>]' -or $path -match 'NNN|XXXX|YYYYMMDD') { continue }

                # Resolve LEXICALLY (GetFullPath normalizes ".." without touching
                # the filesystem), then also try the junction view.
                #
                # ai/claude/ is surfaced to Claude Code as <repoRoot>/.claude/ via a
                # directory junction, and command authors quite reasonably write links
                # relative to THAT path: "../../ai/docs/x.md" from .claude/commands/
                # lexically means <repoRoot>/ai/docs/x.md and is correct for the
                # primary consumer. Resolved physically from ai/claude/commands/ the
                # same link means ai/ai/docs/x.md and looks broken. A link is a
                # violation only when it resolves under NEITHER view.
                $repoParent = Split-Path -Parent $AiRoot
                $candidates = @(
                    [System.IO.Path]::GetFullPath((Join-Path $file.Directory.FullName $path))
                    # Repo-root-relative, e.g. "[Wiki MCP](ai/docs/mcp/wiki.md)" written
                    # from claude/commands/. This is the project's documented path
                    # convention (checkout-relative), not a mistake.
                    [System.IO.Path]::GetFullPath((Join-Path $repoParent $path))
                )

                $claudePrefix = [System.IO.Path]::Combine($AiRoot, "claude") + [System.IO.Path]::DirectorySeparatorChar
                if ($file.Directory.FullName.StartsWith($claudePrefix, [StringComparison]::OrdinalIgnoreCase) -or
                    $file.Directory.FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar) -eq $claudePrefix.TrimEnd([System.IO.Path]::DirectorySeparatorChar))
                {
                    # (repoParent computed above)
                    $suffix = $file.Directory.FullName.Substring($claudePrefix.Length)
                    $junctionDir = [System.IO.Path]::Combine($repoParent, ".claude", $suffix)
                    $candidates += [System.IO.Path]::GetFullPath((Join-Path $junctionDir $path))
                }

                $resolves = $false
                foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $resolves = $true; break } }

                if (-not $resolves)
                {
                    $findings += [PSCustomObject]@{ Check = "broken-link"; File = $rel; Line = $lineNo
                        Detail = "$target does not resolve" }
                }
            }
        }
    }

    $checkOrder = @(
        @{ Name = "call-operator";    Label = "pwsh -Command `"& ...`" instead of -File" }
        @{ Name = "broken-link";      Label = "Relative links that do not resolve" }
        @{ Name = "dangling-command"; Label = "/pw-* references with no command file" }
        @{ Name = "docs-to-skill";    Label = "ai/docs linking into ai/claude/skills" }
        @{ Name = "banned-phrase";    Label = "Banned phrases" }
    )

    foreach ($check in $checkOrder)
    {
        $hits = @($findings | Where-Object { $_.Check -eq $check.Name })
        if ($hits.Count -eq 0)
        {
            Write-Host ("  OK    {0}" -f $check.Label) -ForegroundColor Green
            continue
        }

        Write-Host ("  FAIL  {0}: {1}" -f $check.Label, $hits.Count) -ForegroundColor Red
        $shown = $hits | Select-Object -First $MaxDetail
        foreach ($h in $shown)
        {
            Write-Host ("          {0}:{1}  {2}" -f $h.File, $h.Line, $h.Detail) -ForegroundColor DarkGray
        }
        if ($hits.Count -gt $shown.Count)
        {
            Write-Host ("          ... and {0} more" -f ($hits.Count - $shown.Count)) -ForegroundColor DarkGray
        }
    }

    Write-Host ("-" * 80)
    Write-Host ("Scanned {0} files, {1} violation(s)" -f $allFiles.Count, $findings.Count)

    return @{ Violations = $findings.Count; Findings = $findings }
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
        $allRootLimits = $CoreFileLimits.Clone()
        foreach ($k in $PlatformFileLimits.Keys) { $allRootLimits[$k] = $PlatformFileLimits[$k] }
        $summary["ai"] = Show-LineReport -Title "AI Root (ai/*.md)" -Results $aiResults `
            -Limits $allRootLimits -TotalLimit $CoreTotalLimit -BudgetFiles @($CoreFileLimits.Keys)
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

# Content checks (rules, not sizes)
if ($Section -eq "all" -or $Section -eq "checks")
{
    $aiRootPath = Join-Path $repoRoot "ai"
    if (Test-Path $aiRootPath)
    {
        $summary["checks"] = Test-CorpusRules -AiRoot $aiRootPath `
            -RuleDefiningFiles $RuleDefiningFiles -BannedPhrases $BannedPhrases -MaxDetail $MaxDetail
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

    $checkViolations = if ($summary.ContainsKey("checks")) { $summary["checks"].Violations } else { 0 }

    $hardFailures = $totalErrors + $totalCoreViolations + $checkViolations
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
        if ($checkViolations -gt 0)     { Write-Host "  Content-check violations: $checkViolations (see Content Checks above)" -ForegroundColor Red }
        if ($totalRefactor -eq 0 -and $totalReview -eq 0 -and $totalCoreViolations -eq 0 -and -not $coreTotalViolated -and $checkViolations -eq 0) { Write-Host "  Clean" -ForegroundColor Green }

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
    # Content-check violations are correctness bugs (a dangling /pw-* reference,
    # a link that 404s, a prohibited invocation), not size debt - they fail.
    if ($summary[$key].Violations -gt 0)     { $exitCode = 1 }
}
exit $exitCode
