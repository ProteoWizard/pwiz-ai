# Verify the mean-N port is line-for-line equivalent to the pre-decomposition branch.
#
# The port moved code out of the deleted PercolatorFdr.cs into the #4490 files, which means
# every cross-class call gained a qualifier. Strip the qualifiers introduced by the move and
# the two sides should reduce to the same added-line multiset. Anything left in the diff is a
# real difference that needs a human look - that is exactly what this is for.

$repo = 'C:\proj\pwiz-work1'
$out  = 'C:\Users\brendanx\AppData\Local\Temp\claude\C--proj\0903ae24-3417-40b2-a979-c6d26001f2cc\scratchpad'

function Get-AddedLines {
    param([string[]]$DiffLines)
    $DiffLines |
        Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') } |
        ForEach-Object { $_.Substring(1) }
}

function Normalize {
    param([string[]]$Lines)
    $Lines | ForEach-Object {
        $s = $_
        # Qualifiers the decomposition forced onto calls that used to be intra-class.
        foreach ($q in 'TargetDecoyCompetition.', 'PercolatorQValues.', 'PercolatorSampling.',
                       'PercolatorEntry.', 'StreamingFdr.', 'PercolatorFdr.') {
            $s = $s.Replace($q, '')
        }
        # Collapse whitespace so re-wrapped argument lists compare equal.
        ($s -replace '\s+', ' ').Trim()
    } | Where-Object { $_.Length -gt 0 }
}

# BRANCH side: the four commits as they stood on top of 61fa751304.
$branch = @()
foreach ($f in 'pwiz_tools/Osprey/Osprey.Core/OspreyEnvironment.cs',
                'pwiz_tools/Osprey/Osprey.FDR/PercolatorFdr.cs',
                'pwiz_tools/Osprey/Osprey.Test/FdrTest.cs') {
    $branch += Get-AddedLines (git -C $repo diff 61fa751304..mean-best-n-preDecomp -- $f)
}
$branch += (git -C $repo show mean-best-n-preDecomp:pwiz_tools/Osprey/Osprey.Test/PercolatorMeanBest2Test.cs)

# PORT side: the working tree against master.
$port = @()
$port += Get-AddedLines (git -C $repo diff)
$port += (Get-Content (Join-Path $repo 'pwiz_tools\Osprey\Osprey.Test\MeanBestNAggregationTest.cs'))

$bn = Normalize $branch | Sort-Object
$pn = Normalize $port   | Sort-Object

$bn | Set-Content (Join-Path $out 'branch-norm.txt')
$pn | Set-Content (Join-Path $out 'port-norm.txt')

"branch normalized lines: $($bn.Count)"
"port   normalized lines: $($pn.Count)"
""
"=== in BRANCH but not in PORT ==="
(Compare-Object $bn $pn -PassThru | Where-Object { $_.SideIndicator -eq '<=' })
""
"=== in PORT but not in BRANCH ==="
(Compare-Object $bn $pn -PassThru | Where-Object { $_.SideIndicator -eq '=>' })
