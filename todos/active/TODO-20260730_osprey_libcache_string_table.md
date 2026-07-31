# TODO-20260730_osprey_libcache_string_table.md

## Branch Information
- **Branch**: `Skyline/work/20260730_osprey_libcache_string_table`
- **Base**: `master`
- **Created**: 2026-07-30
- **Status**: In Progress
- **Module**: `osprey`
- **PR**: (pending)

## Problem

Loading the 6.3M-entry SEA-AD entrapment library from its `.libcache` takes **168 s**,
during which Osprey prints **nothing at all**. Measured on the TDP-43 10-file run
(`D:\test\osprey-runs\tdp43-plasma-ev\runs\tdp43-10files-libdecoy-r1.0-protein-compact-picklda\run.log`):

```
18:42:54  [TASK] PerFileScoring:starting
18:45:42  Interned library strings: 10481622 distinct / 21174537 total (50.5% collapsed)
18:45:42  Loaded 6324700 library entries from cache '...carafe_spectral_library.tsv.libcache'
```

Two separate defects, discovered together.

### 1. The cache is SLOWER than parsing the source it caches

Parsing the 13 GB source TSV took ~83 s on the same machine and library; loading the
2.21 GB binary cache took 168 s. The cache exists to be the fast reload path
(`LibraryLoader.cs:46`, "Matches Rust's .libcache mechanism for fast reload") and is
currently the slow one. At 2.21 GB in 168 s (~13 MB/s) it is nowhere near I/O bound.

**Caveat on that comparison, to be re-measured cleanly:** the 83 s TSV parse ran minutes
after another run had read the same 13 GB file, so it was probably served from the OS page
cache on this 128 GB box. The two numbers are therefore not a controlled A/B. The 168 s
itself is solid, and is the number that matters.

### Root cause

`LibraryCache.SaveCache` (`Osprey.IO/LibraryCache.cs:87-144`) writes every string INLINE,
per entry, with no string table:

```csharp
foreach (var entry in entries)
{
    WriteString(w, entry.Sequence);
    WriteString(w, entry.ModifiedSequence);
    ...
    foreach (string pid in entry.ProteinIds)  WriteString(w, pid);
    foreach (string gn in entry.GeneNames)    WriteString(w, gn);
}
```

The in-memory list being saved is ALREADY interned - 6.3M entries sharing 10.5M distinct
strings - but `WriteString` serializes the value, so every shared reference is expanded
back into a full copy on disk. The cache faithfully reproduces the source TSV's
redundancy: **21,174,537 string occurrences of 10,481,622 distinct values**.

`LoadCache` (`:244-250`) then re-does the dedup work the parse already did, on every load:

```csharp
var interner = new LibraryStringInterner();
string sequence         = interner.Intern(ReadString(r));
string modifiedSequence = interner.Intern(ReadString(r));
```

That is why both paths log an identical `Interned library strings:` line - it is the same
work happening twice, once per run, forever.

### 2. Both library load paths are silent

`LibraryLoader.cs:134` logs `"Loading spectral library from {0}..."` only AFTER the cache
attempt, so the cache path prints nothing before its 168 s of silence. The source-parse
path at least announces itself, then goes silent for ~71 s.

`Osprey.Core/ProgressReporter.cs` already exists for exactly this - 5 s
`IO_INTERVAL_SECONDS` throttle, heading on construction, forced final 100%, and an idle
heartbeat added because "an 82-file Stage-6 rescore went ~1 h silent this way". `Osprey.IO`
already references `Osprey.Core` and already uses it in `MzmlReader` and
`ParquetScoreCache`. The library load path was simply never wired up.

Brendan's bar: **"30 seconds is allowable. 3 minutes is not."**

## Plan

Two commits on this branch; splittable into two PRs if review prefers.

1. **Wire `ProgressReporter` into both library load paths.** `LibraryCache.LoadCache` has a
   determinate loop with the count read from the header (`:237`, `:246`), so it needs no new
   plumbing. Also cover `DiannTsvLoader.Load`. Small and independently useful - it helps
   every long phase regardless of what the format does.
2. **Add a string table to the `.libcache` format** and bump `VERSION`. Write the distinct
   strings once, then 4-byte indices at the use sites.

Expect from (2): ~21.2M hash-and-probe interning operations collapse to ~10.5M done once up
front, the 21.2M use sites become plain indexed reads, ~21.2M transient string allocations
during load drop to ~10.5M retained ones, and the file shrinks (accessions and modified
sequences are well over 4 bytes each). **Measure, do not promise a number.**

## Constraints

- **Format change - bump `VERSION`.** Existing `.libcache` files become unreadable and are
  rebuilt from source. The existing version check already handles that path gracefully
  (`LibraryCacheStatus.Invalid` -> rebuild). Cost is one rebuild per library.
- **Rust compatibility is NOT a constraint.** Confirmed with Brendan 2026-07-30: the Rust
  tree is a dying codebase, all innovation is in C#, and the two implementations never need
  to read each other's cache files. What must be preserved is **equal OUTPUT**, which is
  what the cross-impl comparison checks. So this is a one-tree change; do NOT mirror it into
  `maccoss/osprey`.
- **Output must be byte-identical.** Only string object identity changes, never values.

## Gates

- `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
- Round-trip tests in `Osprey.Test/IOTest.cs` already cover the cache
  (identity hash, version rejection, empty, corrupt, omit-fragments, peak-less). Add one
  that a library with heavily repeated accessions round-trips to equal VALUES, and one
  asserting the new version rejects an old-version file.
- `pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` - the standing correctness gate.
  Library load feeds everything, so this is what proves output unchanged.
- Re-measure the 6.3M-entry load on the TDP-43/SEA-AD entrapment library and record
  before/after in this TODO.

## Provenance

Found while validating settings for the first TDP-43 Plasma EV-Quant (164-file) runs, not
by looking for it - the 168 s showed up as the largest reporting gap in
`ai/scripts/perfviz.py` output. See `ai/scripts/Osprey/TDP43/README.md`.
