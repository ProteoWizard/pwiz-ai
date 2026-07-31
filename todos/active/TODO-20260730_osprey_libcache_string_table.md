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

### 1. ~~The cache is SLOWER than parsing the source it caches~~ REFUTED 2026-07-30

**This was wrong, and the string-table rationale largely goes with it.** The claim rested
on one uncontrolled comparison (168 s observed in a production run vs ~83 s for a TSV parse
that was probably page-cache warm). Measured properly with `Measure-LibLoad.ps1`, four
conditions, OS file cache evicted via `Clear-StandbyCache.ps1` for the cold ones:

| condition | path | load | save |
|---|---|---|---|
| cache-cold | `.libcache` | **12 s** | - |
| cache-warm | `.libcache` | **11 s** | - |
| tsv-cold | source TSV | **71 s** | 9 s |
| tsv-warm | source TSV | **72 s** | 7 s |

The binary cache is **~6x FASTER** than parsing its source, which is exactly what it is
for. It is also nearly cold/warm-independent (12 vs 11 s), so it is not I/O bound - the
2.21 GB read is not the cost.

Reproducing the production command line EXACTLY (10 files, `--decoy-pairing-manifest`,
`--model-diagnostics`, `--threads 30`) gives **11 s** for the cache load and 25 s to a
fully paired library. So the 168 s was not caused by the configuration.

**What the 168 s most likely was, NOT proven:** that run started 20 s after the 6-file
control run exited, with the OS still flushing ~16 GB of freshly written parquets and a
saturated page cache, all on the same D: volume. Transient I/O contention is the leading
explanation. It is worth knowing that the 163-file run does a single library load at
startup with no preceding run, so it should see ~12-25 s, not 168 s.

**Lesson worth keeping:** a single timing taken from a production log, with another run's
I/O still draining, is not a measurement. The dedicated harness disagreed with it by 14x.

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

1. **Wire `ProgressReporter` into both library load paths.** DONE - commit `8ba64ff`.
   `LibraryCache.LoadCache` had a determinate loop with the count already read from the
   header (`:237`, `:246`), so it needed no new plumbing; the loop is now inside a
   `ProgressReporter` (braces + re-indent, per STYLEGUIDE "Take the bigger diff", which uses
   this exact pattern as its example). `DiannTsvLoader.Load` reports over BYTES via
   `ProgressStream`, mirroring `MzmlReader`; wired in `Load` rather than `ParseReader` so the
   latter stays a plain `TextReader` entry point for tests.

   **Verified by observation, not by assertion.** The unit tests pass but MSTest captures
   `OspreyOutput.Out`, so they do not prove the lines appear. Running the real 2.21 GB cache:

   ```
   20:16:24  Loading library cache (6324700 entries)...
   20:16:29    2%
   20:16:34    4%
   20:16:39    6%
   20:16:44    9%
   ```

   Exactly 5 s apart (`IO_INTERVAL_SECONDS`). Longest silence on that path: 168 s -> 5 s.
   Gates: 556/556 tests, ReSharper 0 warnings / 0 errors on net472 and net8.0.
2. ~~**Add a string table to the `.libcache` format**~~ **DOWNGRADED - do not do this yet.**
   The design observation stands: `SaveCache` writes every string inline, so the cache
   stores 21,174,537 occurrences of 10,481,622 distinct values and `LoadCache` re-interns
   them on every load. But the measurement above removes the reason to act on it. The cache
   loads in 11-12 s, already 6x faster than parsing its source; a string table might take
   that to single digits and shrink the file, against a format-version bump, a rebuild of
   every existing `.libcache`, and new round-trip tests.

   That is a real but small optimization, not the fix for a pathology - which is what it
   looked like when the premise was a 168 s load. Revisit only if library load ever shows
   up as a genuine cost (e.g. a much larger library, or many short runs), and size it
   against the 11 s baseline rather than the retracted 168 s.

3. **Possible third site, lower priority:** `BuildClassificationFromLibrary`
   (`ModelDiagnostics/ModelDiagnosticsReport.cs:320`) already prints a heading - added for
   this same reason ("ran for minutes at the top of first-pass FDR") - but has no progress
   inside it, so it still shows as a **32-37 s** gap (control 6-file: 37 s and 32 s;
   10-file: 33 s). That is right at the 30 s bar rather than over it, and the work is
   O(library size) not O(files), so it should stay ~35 s at 163 files rather than growing.
   `EntrapmentPairing.Build` plus a determinate `foreach` over `libraryById` - same
   treatment would apply. Do it only if the string table does not already shrink it.

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
