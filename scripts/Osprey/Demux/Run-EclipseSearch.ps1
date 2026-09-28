# Eclipse EV13 + EV14 demultiplexed by Osprey.DemuxTool --scheme staggered, then an Osprey search
# with the flags of the earlier msconvert and Osprey-default arms. -Name names the arm:
# D:\test\osprey-runs\eclipse-staggered\<Name> (mzML), search-<Name> (search), <Name>-cache.
param([string]$Name = 'cs-persweep-w', [string]$Tool = '', [int]$DemuxThreads = 10,
    [string]$Exe = 'D:\test\osprey-runs\_bin\ztscan-persweep-osprey-0f217a3\Osprey.exe', [int]$Threads = 16)
$ErrorActionPreference = 'Stop'
$root = 'D:\test\osprey-runs\eclipse-staggered'
$in = Join-Path $root $Name
$out = Join-Path $root "search-$Name"
$cache = Join-Path $root "$Name-cache"
$stems = 'Ecl_2022_0705_Beads_EV13_SAXN_12mz_10', 'Ecl_2022_0705_Beads_EV14_SAXN_12mz_17'
New-Item -ItemType Directory -Force $in, $out, $cache | Out-Null
$libcache = Join-Path $cache 'carafe_spectral_library+decoy+entrapment.tsv.libcache'
if (-not (Test-Path $libcache)) {
    Copy-Item (Join-Path $root 'msconvert\carafe_spectral_library+decoy+entrapment.tsv.libcache') $cache
}
if ($Tool) {
    foreach ($stem in $stems) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $Tool --in "D:\demux-test-data\Eclipse-staggered\$stem.raw" --out (Join-Path $in "$stem.mzML") --scheme staggered `
            --threads $DemuxThreads *> (Join-Path $in "$stem.log")
        '{0}: exit {1}, {2:F0} s' -f $stem, $LASTEXITCODE, $sw.Elapsed.TotalSeconds
    }
}
$lib = 'D:\demux-test-data\Eclipse-staggered\carafe_spectral_library+decoy+entrapment.tsv'
$sw = [Diagnostics.Stopwatch]::StartNew()
& $Exe -i (Join-Path $in "$($stems[0]).mzML") -i (Join-Path $in "$($stems[1]).mzML") `
    -l $lib -o (Join-Path $out 'output.blib') --resolution hram --fdr-level precursor --protein-fdr 0.01 --decoys-in-library `
    --fdrbench (Join-Path $out 'fdrbench.tsv') --report (Join-Path $out 'report.tsv') `
    --cache-dir $cache --output-dir $out --threads $Threads --timestamp --memstamp `
    --log-file (Join-Path $out 'osprey.log') *> (Join-Path $out 'console.log')
"search-${Name}: exit $LASTEXITCODE, $([math]::Round($sw.Elapsed.TotalSeconds)) s"
