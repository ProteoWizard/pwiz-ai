# TODO-osprey_library_fragment_array_compaction.md -- Further resident-library compaction (post #4381)

## Context

#4381 (`Shrank the resident spectral library with value-struct fragments and string
interning`, Fixes #4372) took the resident Carafe library from ~4.9 -> ~3.2 GB by
making `LibraryFragment` / `FragmentAnnotation` value structs (dropping tens of millions
of tiny heap objects) and interning the repeated per-entry strings. This is the accepted,
output-preserving baseline. These are the next levers if we need to push further toward
Mike's target: **84 files today, 300+ files on a 64 GB machine (DIA-NN-class)**.

After #4381 the fragment storage is effectively an **array of structs**, but per entry:
`LibraryEntry.Fragments` is a `List<LibraryFragment>`, so a 3.17M-entry library holds 3.17M
`List<>` objects, each with (a) a separate backing `LibraryFragment[]` on the heap and
(b) growth slack (Count < Capacity). At ~tens of bytes of list/array overhead plus slack
per entry, that is meaningful fixed overhead on top of the fragment payload, and large
per-entry arrays can land on the Large Object Heap (LOH) and fragment it.

## Ideas (roughly increasing effort)

1. **Trim per-entry list slack.** Cheapest win: `List<LibraryFragment>.Capacity = Count`
   (TrimExcess) after each entry's fragments are finalized at load, or load straight into a
   right-sized array. Removes the growth slack across 3.17M lists. Verify byte-identical
   (regression.ps1) -- pure allocation change.

2. **Flat shared fragment array (structure-of-arrays or one big AoS).** Replace the
   per-entry `List<LibraryFragment>` with a single library-wide `LibraryFragment[]` plus a
   per-entry `(int offset, int count)` slice (or a `ReadOnlyMemory<LibraryFragment>`). Kills
   3.17M list/array objects and their slack; makes the whole fragment pool one contiguous
   allocation. Downside: entries become views into a shared buffer, so decoy generation /
   any code that rebuilds an entry's fragments needs an append-to-shared or per-entry
   scratch path. Bigger refactor; do behind regression.ps1 + the perf gate.

3. **Pull the Skyline / CommonUtil "Blocked" collection types over PortableUtil.**
   Skyline.Util has `BlockedArray` / `BlockedArrayList` (block-chunked arrays that sidestep
   LOH fragmentation and the 2 GB single-array limit while staying cache-friendly). A flat
   fragment pool at 300+ files could exceed comfortable single-array sizes, so a blocked
   backing store is the natural home. Investigate `pwiz.CommonUtil.Collections` too --
   Nick Shulman has done substantial in-memory-size reduction for Skyline there, so it is
   the most likely source of newer, reusable compact-collection code. Osprey currently only
   depends on PortableUtil; per [[project_ospreysharp_exe_and_shared]] the direction for
   Skyline<->Osprey sharing is via `pwiz_tools\Shared`, not embedding -- so the task is to
   identify which Blocked/collection types to promote into a Shared assembly Osprey can
   reference (or into PortableUtil) rather than copy-paste.

4. **Micro-shrinks (low value, note for completeness).**
   - `IonType : byte` (matches `NeutralLossCode : byte`); a few MB at 3M fragments. The
     cache already maps via `IonTypeToByte`, so backing-type change is cache-neutral.
   - `FragmentAnnotation.CustomLossMass` is an 8-byte double carried on every fragment but
     meaningful only for `Custom` losses (rare). A side-table keyed by fragment index would
     save 8 B/fragment for the common case, at the cost of complexity -- probably not worth
     it vs. the flat-array win, but record it.

## Faster cache load + spectrum cache (Skyline binary-cache techniques)

Separate from the in-memory shrink above: the load PATH itself can adopt the binary-cache
format Skyline has refined for ~17 years (e.g. the `.skyd` ChromatogramCache and the spectrum
caches). Key techniques Osprey's `LibraryCache` (and likely `SpectraCache`) should mine:

- **Counts/offsets in a FOOTER at the end of the file.** Skyline writes the array sizes (and
  per-section offsets) at the END, so the loader seeks to the end, reads the sizes, allocates
  each array at its exact final length once, then reads forward -- no count-prefix guesswork,
  no List<> growth/realloc. Osprey's cache currently writes `entries.Count` as a leading
  prefix; a footer layout additionally lets a random-access/mmapped reader locate any section
  without a full scan.
- **Bulk block reads of blittable struct arrays.** #4381 made `LibraryFragment` a
  reference-free value struct, so a whole entry's (or the whole library's) fragment array can
  be read/written in ONE block copy instead of the current per-field
  `BinaryReader.ReadDouble()/ReadSingle()/...` per fragment. That is the big load-time win the
  struct change unlocks; pair it with the flat shared fragment array (idea 2 above) so the
  on-disk block maps directly to the resident array. The canonical Skyline implementation is
  `pwiz_tools/Skyline/Model/Results/ChromHeaderInfo.cs` -- see its `#region Fast file I/O`
  blocks and the `[StructLayout(LayoutKind.Sequential, Pack = 4)]` structs (with the "CAREFUL:
  this ordering IS the on-disk layout, loaded directly into memory ... to avoid wasted space
  due to alignment" comment). The element count comes from the header/footer so the array is
  allocated at its final length once.

  **CROSS-PLATFORM caveat (important for Osprey):** ChromHeaderInfo's whole-array
  `ReadArray`/`WriteArray` use `FastRead.ReadBytes`/`FastWrite.WriteBytes`, which p-invoke Win32
  `ReadFile`/`WriteFile` -- **Windows-only, so NOT usable as Osprey's shared path** (Osprey must
  run on Linux/HPC). Note Skyline has largely moved OFF whole-array block reads and mostly keeps
  *direct per-struct* reading now. For Osprey use the portable .NET equivalents that give the
  same zero-extra-copy blittable read without p-invoke: `Stream.Read(Span<byte>)` (or
  `System.IO.RandomAccess.Read`) into a buffer, then `MemoryMarshal.Cast<byte, LibraryFragment>`
  / `MemoryMarshal.Read<T>` to reinterpret -- all cross-platform on net8.0. Alternatively keep a
  Win32 fast path but **degrade gracefully to the Span/Stream path off Windows** (via
  `RuntimeInformation.IsOSPlatform`) rather than depend on the p-invoke. Watch explicit
  layout/padding + endianness (x64 LE both sides today, but pin it) so the format stays
  portable and versioned.
- **Memory-mapped / lazy load.** Skyline's caches memory-map and read on demand; for a 300+
  file target where the library is read-mostly, mmapping the fragment block (or lazily paging
  it) keeps it out of the managed heap entirely.
- Applies to the **binary spectrum cache** (`SpectraCache`) too -- same footer + block-read
  pattern for the per-file spectra, which are also large and read-mostly.

Reference: `pwiz_tools/Skyline/Model/Results/ChromHeaderInfo.cs` is the best example of
Skyline's most complex cache with the `Fast file I/O` block-IO pattern (per Brendan);
`ChromatogramCache.cs` / `CacheFormat.cs` are the surrounding footer/format + mmap machinery.
A format change here is a `.libcache` VERSION bump (currently 2), so old caches
rebuild once -- acceptable for a load-speed/memory win, unlike the #4381 byte-preserving change.

## Gates (any of these)

- Correctness: `regression.ps1 -Dataset Stellar` (and `-Dataset All` before a
  behaviour/perf-sensitive merge) must stay byte-identical -- every idea above is intended
  to be pure allocation/layout, output-preserving.
- Coverage gap to close: the byte-identical regression uses the Carafe **TSV** library
  (`DiannTsvLoader`), so it does NOT exercise `BlibLoader`. Any fragment-storage change
  should add or lean on a blib round-trip assertion (see #4381 review note).
- Perf: `Test-PerfGate.ps1` -- fewer/larger allocations should be neutral-to-faster; confirm
  no regression.
- Memory: `OSPREY_LOG_MEMORY` `[MEM library-resident]` post-GC probe (added in #4381) is the
  before/after number to move.

## Related
- #4372 (resident library, closed by #4381), #4355/#4378 (per-file scoring + FDR streaming),
  #4376 (stage-6 reconciliation, #4394) -- the other memory levers toward the 300-file goal.
- Skyline `BlockedArray` / `BlockedArrayList`, `pwiz.CommonUtil.Collections` (Nick Shulman).
