<#
.SYNOPSIS
    On-demand overview of the Osprey backlog held in GitHub Issues.

.DESCRIPTION
    The Osprey backlog lives in GitHub Issues labelled `osprey`, not in
    ai/todos/backlog/. A committed markdown index would go stale the moment an
    issue is opened or closed, so this is a STORED QUERY instead: run it when you
    want the overview, read the artifact, throw it away.

    It queries the issues with `gh`, groups them by type label
    (bug / enhancement / performance / tech-debt / untyped), and writes a
    self-contained review artifact to ai/.tmp/ -- HTML by default (open it in a
    browser; every row links to the issue), or Markdown with -Format Markdown.

    The output is deliberately written to ai/.tmp/ and NEVER into the repo tree.
    It is a review artifact, not a committed file.

    An issue carrying more than one type label is listed once, in the first
    matching group in the order bug, performance, enhancement, tech-debt; its
    full label set is shown on the row either way, so nothing is hidden.

.PARAMETER State
    Which issues to list: open (default), closed, or all.

.PARAMETER Format
    Html (default) or Markdown.

.PARAMETER Label
    The label to filter on. Defaults to `osprey`; override to reuse this for
    another area (e.g. -Label skyline).

.PARAMETER Repo
    The GitHub repository. Defaults to ProteoWizard/pwiz.

.PARAMETER OutFile
    Explicit output path. By default the file is written to ai/.tmp/ as
    osprey-backlog-<state>.<ext>, so re-running overwrites in place and a
    browser refresh shows the current picture.

.PARAMETER Limit
    Maximum issues to fetch (default 500).

.PARAMETER Show
    Open the generated file with the default handler when done.

.EXAMPLE
    pwsh -File './ai/scripts/Osprey/Get-OspreyBacklog.ps1'

    The open Osprey backlog as HTML in ai/.tmp/osprey-backlog-open.html.

.EXAMPLE
    pwsh -File './ai/scripts/Osprey/Get-OspreyBacklog.ps1' -State all -Format Markdown

    Open and closed Osprey issues as Markdown, for pasting into a session note.

.NOTES
    Requires the `gh` CLI, authenticated (`gh auth status`).
#>
[CmdletBinding()]
param(
    [ValidateSet('open', 'closed', 'all')]
    [string]$State = 'open',

    [ValidateSet('Html', 'Markdown')]
    [string]$Format = 'Html',

    [string]$Label = 'osprey',

    [string]$Repo = 'ProteoWizard/pwiz',

    [string]$OutFile,

    [int]$Limit = 500,

    [switch]$Show
)

$ErrorActionPreference = 'Stop'

# Type labels, in the order an issue is assigned to a group when it carries more
# than one. 'untyped' is the catch-all and is not matched against.
$typeOrder = @('bug', 'performance', 'enhancement', 'tech-debt')
$groupTitles = [ordered]@{
    'bug'         = 'Bugs'
    'performance' = 'Performance'
    'enhancement' = 'Enhancements'
    'tech-debt'   = 'Tech debt'
    'untyped'     = 'Untyped'
}

function Get-AiRoot {
    # <ai>/scripts/Osprey/Get-OspreyBacklog.ps1 -> <ai>
    return (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
}

function ConvertTo-HtmlText([string]$text) {
    if ($null -eq $text) { return '' }
    return $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Get-AgeDays([datetime]$when, [datetime]$now) {
    return [int][math]::Floor(($now - $when).TotalDays)
}

function Format-Age([int]$days) {
    if ($days -le 0) { return 'today' }
    if ($days -eq 1) { return '1 day' }
    if ($days -lt 60) { return "$days days" }
    $months = [int][math]::Round($days / 30.4)
    return "$months mo"
}

function Format-Since([int]$days) {
    if ($days -le 0) { return 'today' }
    return "$(Format-Age $days) ago"
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'The gh CLI was not found on PATH. Install it and run `gh auth status`.'
}

Write-Host "Querying $Repo for $State issues labelled '$Label'..."

$fields = 'number,title,labels,updatedAt,createdAt,author,url,state'
$json = gh issue list --repo $Repo --label $Label --state $State --limit $Limit --json $fields
if ($LASTEXITCODE -ne 0) {
    throw "gh issue list failed with exit code $LASTEXITCODE."
}

$issues = @()
if (-not [string]::IsNullOrWhiteSpace($json)) {
    $issues = @($json | ConvertFrom-Json)
}

$now = Get-Date
$generatedAt = $now.ToString('yyyy-MM-dd HH:mm')

# Bucket the issues, and pre-compute the per-row display values once.
$buckets = [ordered]@{}
foreach ($key in $groupTitles.Keys) { $buckets[$key] = [System.Collections.Generic.List[object]]::new() }

foreach ($issue in $issues) {
    $names = @($issue.labels | ForEach-Object { $_.name })
    $group = 'untyped'
    foreach ($type in $typeOrder) {
        if ($names -contains $type) { $group = $type; break }
    }

    $created = [datetime]$issue.createdAt
    $updated = [datetime]$issue.updatedAt

    $buckets[$group].Add([pscustomobject]@{
        Number      = $issue.number
        Title       = $issue.title
        Url         = $issue.url
        State       = $issue.state
        Author      = if ($issue.author) { $issue.author.login } else { '' }
        # The query label and the label that put this row in its group are both
        # implied by the heading; only show what those two do not already say.
        Labels      = @($names | Where-Object { $_ -ne $Label -and $_ -ne $group } | Sort-Object)
        AgeDays     = Get-AgeDays $created $now
        UpdatedDays = Get-AgeDays $updated $now
        Created     = $created.ToString('yyyy-MM-dd')
        Updated     = $updated.ToString('yyyy-MM-dd')
    })
}

foreach ($key in @($buckets.Keys)) {
    $sorted = @($buckets[$key] | Sort-Object UpdatedDays, Number)
    $buckets[$key] = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $sorted) { $buckets[$key].Add($row) }
}

$total = $issues.Count
$stateTitle = switch ($State) { 'open' { 'open' } 'closed' { 'closed' } default { 'open and closed' } }
$heading = "Osprey backlog -- $stateTitle issues labelled '$Label'"

$ext = if ($Format -eq 'Html') { 'html' } else { 'md' }
if (-not $OutFile) {
    $tmpDir = Join-Path (Get-AiRoot) '.tmp'
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir | Out-Null }
    $OutFile = Join-Path $tmpDir "osprey-backlog-$State.$ext"
}

$sb = [System.Text.StringBuilder]::new()

if ($Format -eq 'Html') {
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine("<title>$(ConvertTo-HtmlText $heading)</title>")
    [void]$sb.AppendLine(@'
<style>
:root {
  --bg: #ffffff; --fg: #1c1e21; --muted: #6b7280; --line: #e3e6ea;
  --card: #f7f8fa; --link: #0b57d0; --chip-bg: #eceff3; --chip-fg: #414750;
  --accent: #1d76db;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16181c; --fg: #e6e8eb; --muted: #9aa3ae; --line: #2b2f36;
    --card: #1d2026; --link: #7cb0ff; --chip-bg: #262a31; --chip-fg: #b9c1cb;
    --accent: #4b9bef;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 32px 24px 64px; background: var(--bg); color: var(--fg);
  font: 15px/1.5 -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
}
.wrap { max-width: 1080px; margin: 0 auto; }
h1 { font-size: 22px; margin: 0 0 6px; font-weight: 620; }
.stamp { color: var(--muted); font-size: 13px; margin: 0 0 22px; }
.totals { display: flex; flex-wrap: wrap; gap: 8px; margin: 0 0 28px; padding: 0; list-style: none; }
.totals li {
  background: var(--card); border: 1px solid var(--line); border-radius: 7px;
  padding: 7px 12px; font-size: 13px;
}
.totals b { font-size: 15px; }
h2 {
  font-size: 15px; font-weight: 620; letter-spacing: .01em; margin: 30px 0 10px;
  padding-bottom: 7px; border-bottom: 2px solid var(--accent);
}
h2 .count { color: var(--muted); font-weight: 400; }
table { width: 100%; border-collapse: collapse; font-size: 14px; }
th {
  text-align: left; font-weight: 600; font-size: 12px; text-transform: uppercase;
  letter-spacing: .04em; color: var(--muted); padding: 6px 10px; border-bottom: 1px solid var(--line);
}
td { padding: 9px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
tr:hover td { background: var(--card); }
td.num { white-space: nowrap; font-variant-numeric: tabular-nums; width: 74px; }
td.when { white-space: nowrap; color: var(--muted); font-size: 13px; width: 96px; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
.chip {
  display: inline-block; background: var(--chip-bg); color: var(--chip-fg);
  border-radius: 999px; padding: 1px 8px; font-size: 11px; margin: 3px 4px 0 0;
}
.by { color: var(--muted); font-size: 12px; }
.empty { color: var(--muted); font-style: italic; padding: 10px 0 4px; }
.foot { color: var(--muted); font-size: 12px; margin-top: 40px; border-top: 1px solid var(--line); padding-top: 14px; }
code { background: var(--chip-bg); border-radius: 4px; padding: 1px 5px; font-size: 12px; }
</style>
'@)
    [void]$sb.AppendLine('</head><body><div class="wrap">')
    [void]$sb.AppendLine("<h1>$(ConvertTo-HtmlText $heading)</h1>")
    [void]$sb.AppendLine("<p class=""stamp"">$(ConvertTo-HtmlText $Repo) &middot; generated $generatedAt</p>")

    [void]$sb.AppendLine('<ul class="totals">')
    [void]$sb.AppendLine("<li><b>$total</b> total</li>")
    foreach ($key in $groupTitles.Keys) {
        $n = $buckets[$key].Count
        if ($n -gt 0) { [void]$sb.AppendLine("<li><b>$n</b> $(ConvertTo-HtmlText $groupTitles[$key].ToLower())</li>") }
    }
    [void]$sb.AppendLine('</ul>')

    foreach ($key in $groupTitles.Keys) {
        $rows = $buckets[$key]
        if ($rows.Count -eq 0) { continue }
        [void]$sb.AppendLine("<h2>$(ConvertTo-HtmlText $groupTitles[$key]) <span class=""count"">($($rows.Count))</span></h2>")
        [void]$sb.AppendLine('<table><thead><tr><th>Issue</th><th>Title</th><th>Age</th><th>Updated</th></tr></thead><tbody>')
        foreach ($row in $rows) {
            $chips = ''
            foreach ($name in $row.Labels) {
                $chips += "<span class=""chip"">$(ConvertTo-HtmlText $name)</span>"
            }
            $by = if ($row.Author) { " <span class=""by"">&middot; $(ConvertTo-HtmlText $row.Author)</span>" } else { '' }
            [void]$sb.AppendLine('<tr>')
            [void]$sb.AppendLine("<td class=""num""><a href=""$(ConvertTo-HtmlText $row.Url)"">#$($row.Number)</a></td>")
            [void]$sb.AppendLine("<td><a href=""$(ConvertTo-HtmlText $row.Url)"">$(ConvertTo-HtmlText $row.Title)</a>$by<br>$chips</td>")
            [void]$sb.AppendLine("<td class=""when"" title=""opened $($row.Created)"">$(Format-Age $row.AgeDays)</td>")
            [void]$sb.AppendLine("<td class=""when"" title=""updated $($row.Updated)"">$(Format-Since $row.UpdatedDays)</td>")
            [void]$sb.AppendLine('</tr>')
        }
        [void]$sb.AppendLine('</tbody></table>')
    }

    if ($total -eq 0) {
        [void]$sb.AppendLine('<p class="empty">No issues matched.</p>')
    }

    [void]$sb.AppendLine('<p class="foot">Generated by <code>ai/scripts/Osprey/Get-OspreyBacklog.ps1</code>. This is a review artifact in <code>ai/.tmp/</code> &mdash; re-run it rather than saving it.</p>')
    [void]$sb.AppendLine('</div></body></html>')
}
else {
    [void]$sb.AppendLine("# $heading")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("$Repo -- generated $generatedAt -- **$total** issue(s)")
    [void]$sb.AppendLine('')
    foreach ($key in $groupTitles.Keys) {
        $rows = $buckets[$key]
        if ($rows.Count -eq 0) { continue }
        [void]$sb.AppendLine("## $($groupTitles[$key]) ($($rows.Count))")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('| Issue | Title | Age | Updated |')
        [void]$sb.AppendLine('|---|---|---|---|')
        foreach ($row in $rows) {
            $title = $row.Title.Replace('|', '\|')
            $extra = if ($row.Labels.Count) { ' _(' + ($row.Labels -join ', ') + ')_' } else { '' }
            [void]$sb.AppendLine("| [#$($row.Number)]($($row.Url)) | $title$extra | $(Format-Age $row.AgeDays) | $(Format-Since $row.UpdatedDays) |")
        }
        [void]$sb.AppendLine('')
    }
    if ($total -eq 0) { [void]$sb.AppendLine('_No issues matched._') }
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine('Generated by `ai/scripts/Osprey/Get-OspreyBacklog.ps1` into `ai/.tmp/` -- re-run it rather than saving it.')
}

$sb.ToString() | Set-Content -Path $OutFile -Encoding utf8

Write-Host ''
Write-Host "$total issue(s):" -NoNewline
foreach ($key in $groupTitles.Keys) {
    $n = $buckets[$key].Count
    if ($n -gt 0) { Write-Host " $n $key;" -NoNewline }
}
Write-Host ''
Write-Host "Wrote $OutFile"

if ($Show) { Invoke-Item $OutFile }
