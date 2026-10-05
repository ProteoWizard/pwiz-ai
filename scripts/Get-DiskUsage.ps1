<#
.SYNOPSIS
    Report how much disk a set of folders really uses when they share files through hard
    links, and how much deleting each one would actually free.

.DESCRIPTION
    The Osprey dataset runners stage earlier stages' outputs into a new run directory with
    hard links (OspreyDatasetRun.psm1, `New-Item -ItemType HardLink`), so one 1.6 GB parquet
    can appear in a dozen run folders while occupying the disk once. Explorer, `dir /s` and
    `Get-ChildItem | Measure-Object Length` all count it once per path, so a folder of runs
    reports several times the disk it holds, and "delete this run" frees far less than its
    size suggests.

    This script identifies every file by its NTFS identity (volume serial number + file
    index, from GetFileInformationByHandle) and reads the file's own link count, so the
    answer does not depend on what else was scanned:

      Apparent  - sum of every path's length (what Explorer shows).
      Unique    - each file counted once within the row: the disk the row's contents occupy.
      Freed     - files whose EVERY link lies inside the row. Deleting the row frees exactly
                  this. A link anywhere else on the volume - scanned or not - keeps the file,
                  because the comparison is against the link count NTFS stores in the file.
      Shared    - Unique minus Freed: kept alive by links outside the row.

    By default each immediate subfolder of -Path is one row, loose files directly under
    -Path form a "(files)" row, and a TOTAL row covers everything scanned: its Unique is the
    disk the whole tree occupies, and its Freed is what deleting the whole tree would free.

    Reparse points (symbolic links, junctions) are not followed and not counted, so a
    linked-in directory cannot be counted twice. Lengths are logical file sizes; NTFS
    compression and sparse files are not accounted for (none of the Osprey outputs use them).

.PARAMETER Path
    One or more folders, comma-separated in ONE argument under `pwsh -File` ("D:\a,E:\b").
    With several, each is scanned separately and the TOTAL row covers them all - a file
    linked from two of them is still counted once there.

.PARAMETER NoChildren
    Report each -Path as a single row instead of one row per immediate subfolder.

.PARAMETER SortBy
    Name (default), Freed, Unique or Apparent. Size sorts are descending.

.PARAMETER Unit
    GB (default), MB or TB for the size columns.

.EXAMPLE
    # Which SEA-AD runs are worth deleting, and what each would actually free
    pwsh -File ./ai/scripts/Get-DiskUsage.ps1 -Path D:\Users\brendanx\test\osprey-runs\sea-ad\runs -SortBy Freed

.EXAMPLE
    # Real footprint of the whole test area across both drives
    pwsh -File ./ai/scripts/Get-DiskUsage.ps1 -Path "D:\Users\brendanx\test\osprey-runs,E:\Users\brendanx\test\osprey-runs" -NoChildren
#>
#requires -Version 7
param(
    # Also split on commas: `pwsh -File` cannot pass an array, so several folders arrive as
    # one "a,b" string.
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,
    [switch]$NoChildren,
    [ValidateSet('Name', 'Freed', 'Unique', 'Apparent')]
    [string]$SortBy = 'Name',
    [ValidateSet('MB', 'GB', 'TB')]
    [string]$Unit = 'GB'
)

$ErrorActionPreference = 'Stop'
$Path = @($Path -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if (-not ('HardLinkUsage' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class HardLinkUsage
{
    public struct FileRecord
    {
        public uint Volume;
        public ulong Index;
        public long Length;
        public uint Links;
    }

    public sealed class Group
    {
        public string Name;
        public List<FileRecord> Files = new List<FileRecord>();
    }

    public sealed class Row
    {
        public string Name;
        public long Paths;
        public long Apparent;
        public long Unique;
        public long Freed;
    }

    public static int Errors;

    [StructLayout(LayoutKind.Sequential)]
    private struct BY_HANDLE_FILE_INFORMATION
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share,
        IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle,
        out BY_HANDLE_FILE_INFORMATION info);

    private const uint FILE_READ_ATTRIBUTES = 0x80;
    private const uint SHARE_ALL = 0x1 | 0x2 | 0x4;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;

    public static void AddDirectory(Group group, string dir)
    {
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint
        };
        foreach (string file in Directory.EnumerateFiles(dir, "*", options))
            AddFile(group, file);
    }

    public static void AddFile(Group group, string file)
    {
        using (SafeFileHandle h = CreateFileW(@"\\?\" + file, FILE_READ_ATTRIBUTES, SHARE_ALL,
            IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
            IntPtr.Zero))
        {
            BY_HANDLE_FILE_INFORMATION info;
            if (h.IsInvalid || !GetFileInformationByHandle(h, out info))
            {
                Errors++;
                return;
            }
            group.Files.Add(new FileRecord
            {
                Volume = info.VolumeSerialNumber,
                Index = ((ulong)info.FileIndexHigh << 32) | info.FileIndexLow,
                Length = ((long)info.FileSizeHigh << 32) | info.FileSizeLow,
                Links = info.NumberOfLinks
            });
        }
    }

    // One row per group, then the TOTAL row over every group together.
    public static List<Row> Summarize(List<Group> groups)
    {
        var rows = new List<Row>();
        var all = new List<FileRecord>();
        foreach (Group g in groups)
        {
            rows.Add(SummarizeFiles(g.Name, g.Files));
            all.AddRange(g.Files);
        }
        rows.Add(SummarizeFiles("TOTAL", all));
        return rows;
    }

    private static Row SummarizeFiles(string name, List<FileRecord> files)
    {
        var row = new Row { Name = name };
        // Links seen in this row per file identity; the file's length rides along.
        var seen = new Dictionary<(uint, ulong), (long Length, uint Links, uint Seen)>();
        foreach (FileRecord f in files)
        {
            row.Paths++;
            row.Apparent += f.Length;
            var key = (f.Volume, f.Index);
            if (seen.TryGetValue(key, out var s))
                seen[key] = (s.Length, s.Links, s.Seen + 1);
            else
                seen[key] = (f.Length, f.Links, 1);
        }
        foreach (var s in seen.Values)
        {
            row.Unique += s.Length;
            if (s.Seen >= s.Links)
                row.Freed += s.Length;
        }
        return row;
    }
}
'@
}

[HardLinkUsage]::Errors = 0
$groups = [System.Collections.Generic.List[HardLinkUsage+Group]]::new()
foreach ($p in $Path) {
    $root = (Resolve-Path -LiteralPath $p).ProviderPath
    if ($NoChildren) {
        $g = [HardLinkUsage+Group]::new()
        $g.Name = $root
        [HardLinkUsage]::AddDirectory($g, $root)
        $groups.Add($g)
        continue
    }
    foreach ($dir in Get-ChildItem -LiteralPath $root -Directory -Attributes !ReparsePoint) {
        $g = [HardLinkUsage+Group]::new()
        $g.Name = if ($Path.Count -gt 1) { Join-Path $root $dir.Name } else { $dir.Name }
        [HardLinkUsage]::AddDirectory($g, $dir.FullName)
        $groups.Add($g)
    }
    $loose = Get-ChildItem -LiteralPath $root -File -Attributes !ReparsePoint
    if ($loose) {
        $g = [HardLinkUsage+Group]::new()
        $g.Name = if ($Path.Count -gt 1) { Join-Path $root '(files)' } else { '(files)' }
        foreach ($f in $loose) {
            [HardLinkUsage]::AddFile($g, $f.FullName)
        }
        $groups.Add($g)
    }
}

$divisor = switch ($Unit) { 'MB' { 1MB } 'TB' { 1TB } default { 1GB } }
$rows = foreach ($r in [HardLinkUsage]::Summarize($groups)) {
    # Name last, so a long path cannot push the numbers off the table.
    $row = [ordered]@{ Files = $r.Paths }
    $row["Apparent$Unit"] = [math]::Round($r.Apparent / $divisor, 1, [MidpointRounding]::AwayFromZero)
    $row["Unique$Unit"] = [math]::Round($r.Unique / $divisor, 1, [MidpointRounding]::AwayFromZero)
    $row["Freed$Unit"] = [math]::Round($r.Freed / $divisor, 1, [MidpointRounding]::AwayFromZero)
    $row["Shared$Unit"] = [math]::Round(($r.Unique - $r.Freed) / $divisor, 1, [MidpointRounding]::AwayFromZero)
    $row.Name = $r.Name
    [pscustomobject]$row
}
$total = $rows | Select-Object -Last 1
$body = $rows | Select-Object -SkipLast 1
$body = if ($SortBy -eq 'Name') {
    $body | Sort-Object Name
}
else {
    $body | Sort-Object "$SortBy$Unit" -Descending
}
@($body) + $total | Format-Table -AutoSize
if ([HardLinkUsage]::Errors -gt 0) {
    Write-Warning ("{0} file(s) could not be opened and are not counted." -f [HardLinkUsage]::Errors)
}
