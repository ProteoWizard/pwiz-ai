<#
    Evict the Windows OS standby (file cache) list WITHOUT any external tool, so
    the next read of a large cached file (e.g. the 6.3 GB .spectra.bin) is cold.

    Mechanism: allocate a private-committed memory balloon and TOUCH every 4 KB
    page (forcing real physical backing). To satisfy the private commit the memory
    manager reclaims the standby list first (cheapest pages), evicting cached file
    data. On process exit the balloon is released back to the OS as FREE (not
    re-cached), so the target file stays cold for the next process.

    Self-validating: if a subsequent Osprey run still shows a ~0.5s warm load
    slice, the balloon was too small -- re-run with a larger -TargetGB.
#>
param([int]$TargetGB = 42)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function AvailGB {
    try { [math]::Round((Get-Counter '\Memory\Available MBytes' -ErrorAction Stop).CounterSamples.CookedValue / 1024, 1) }
    catch { -1 }
}

Add-Type @'
using System;
using System.Collections.Generic;
public static class Balloon {
    // Allocate `gb` 1-GiB arrays and touch every 4 KB page so each is physically
    // backed (forcing standby reclaim). Stops early on OutOfMemory.
    public static List<byte[]> Fill(int gb) {
        var held = new List<byte[]>();
        for (int i = 0; i < gb; i++) {
            try {
                var b = new byte[1073741824];
                for (long p = 0; p < b.LongLength; p += 4096) b[p] = 1;
                held.Add(b);
            } catch (OutOfMemoryException) { break; }
        }
        return held;
    }
}
'@

$before = AvailGB
Write-Host ("Available before: {0} GB; ballooning up to {1} GB..." -f $before, $TargetGB)
$held = [Balloon]::Fill($TargetGB)
$after = AvailGB
Write-Host ("Ballooned {0} GB; available now {1} GB (standby reclaimed -> target file evicted)" -f $held.Count, $after)
# Intentionally no explicit free: process exit returns all pages to the OS free
# list. Holding $held until now guaranteed the standby eviction already happened.
