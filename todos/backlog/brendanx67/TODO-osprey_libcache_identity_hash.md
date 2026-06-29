# TODO-osprey_libcache_identity_hash.md

## Summary
Follow-up PR that hardens the `.libcache` staleness guard Mike added in **PR #4338**
("Osprey: ignore a .libcache that is older than its source library"). #4338 is correct
and safe and we are letting it merge as-is. This follow-up replaces its mtime-ordering
check with the library **identity hash** Osprey already uses everywhere else, stamped
into the libcache file itself — a tighter, explicit, size-aware guarantee.

**Status**: Backlog (not started; design settled). **Type**: I/O-layer correctness hardening.
**Blocked on**: PR #4338 merging to master first (this builds directly on its files).
**Origin**: `/pw-review 4338` discussion with Brendan, 2026-06-29.

## Background: what #4338 does and why it isn't enough
`LibraryLoader.Load` trusted any existing `.libcache` whenever the file merely existed.
When a library is rebuilt in place (same path) without clearing the cache, Osprey loaded
the **previous** build; its decoys/pairing no longer match the current decoy-pairing
manifest, so manifest pairing collapses (~0.4% observed on a rebuilt 3.2M-entry library)
and `--decoys-in-library` scoring aborts at the pairing-fraction threshold.

#4338 gates reuse on `LibraryLoader.IsCacheFresh(cachePath, sourcePath)` = cache mtime
`>=` source mtime (trust cache when source missing). This fixes the reported in-place
rebuild, but mtime-ordering is brittle:
- **One-directional.** It only catches "source newer than cache." A *different* library
  swapped in with an equal-or-older mtime — git checkout, `rsync --times`, `cp -p`, or an
  unzip that preserves a historical timestamp — passes as "fresh" and loads the wrong
  build's decoys: the original bug, via a different trigger.
- **Order ≠ identity.** It infers a relationship from creation order rather than asking
  "is this the same library this cache was built from."

## What the rest of pwiz/Osprey already does (the inconsistency #4338 introduces)
Every other library-keyed cache validates through one canonical identity:
**`SearchIdentity.LibraryIdentityHash()`** (`Osprey.Core/SearchIdentity.cs:143`) — a
SHA-256 of `file_name + size + mtime(whole Unix seconds)`, "same recipe as Rust's
`library_identity_hash`". It is stamped on write and compared on read:
- `.scores.parquet` footer `osprey.library_hash` (`PerFileScoringTask.cs:203`,
  `ReconciledParquetWriter.cs:202`); `ParquetScoreCache` hard-aborts on mismatch
  (`ParquetScoreCache.cs:1189-1227`), covered by `TestMetadataLibraryHashMismatch...`.
- reconciliation envelope `LibraryHash` (`FirstJoinTask.cs:722`, `ReconciliationFile.cs:80`).

The `.libcache` is the **lone** library-derived artifact never wired to this. #4338 adds a
*second, weaker* invalidation mechanism beside the one already standardized on. This
follow-up converges them.

## Why the identity hash is the right fix
- **Symmetric** — any size/mtime change invalidates (catches the older-but-different swap
  #4338 misses), not just "newer source".
- **Size-aware** — two builds of a 3.2M library can land in the same coarse mtime bucket
  (FAT/SMB ~2 s) but differ in length; size catches it. (Honest limit: it is still
  *metadata*, not a content hash — equal size+mtime with different content is conceivable.
  This is Osprey's deliberate fast-identity-over-content tradeoff, documented in the
  `SearchIdentity` header; the size term is what defends the timestamp-preserving
  unzip/restore case, which is the realistic one.)
- **Explicit** — identity lives *in the cache file content*, not as an implicit property
  ("this cache must always carry the source's mtime"). Preferred over the even-smaller
  alternative of stamping the cache's mtime == source mtime and comparing `==`, which
  overloads mtime as a data channel and trips age-based tooling / LRU eviction.
- **Consistent + parity-aligned** — one mechanism, the same one `.scores.parquet` uses,
  and the config already carries it (`config.Identity` is in hand inside `LibraryLoader`).

## Design (settled)
Three files in `pwiz_tools/Osprey`. Net is ~a dozen lines more than #4338's helper and it
deletes `IsCacheFresh`.

**`Osprey.IO/LibraryCache.cs`** — stamp + check identity in the header:
- Bump `VERSION` `1 -> 2`. v2 writes the identity hash (length-prefixed UTF-8 string)
  immediately after the version, before `count`. v1 has a different header layout and no
  identity → reads as `Invalid` and is rebuilt once (desired).
- Add `public enum LibraryCacheStatus { Loaded, IdentityMismatch, Invalid }`.
- `SaveCache(string path, List<LibraryEntry> entries, string libraryHash)` — writes
  `libraryHash ?? ""` into the header.
- `LoadCache(string path, string expectedLibraryHash, out LibraryCacheStatus status)` —
  on bad magic / `version != VERSION` → `Invalid`, null. Read stored hash; if
  `expectedLibraryHash` non-empty and `!Ordinal.Equals` → `IdentityMismatch`, null
  (entries NOT read — skips a multi-GB read on a stale cache). Else read entries,
  `Loaded`.
- Keep `LoadCache(string path)` as a thin overload calling the above with
  `expectedLibraryHash = null` (identity-agnostic; used by round-trip tests and the
  source-missing fallback).

**`Osprey.IO/LibraryLoader.cs`** — drive reuse off identity; remove `IsCacheFresh`:
```
bool sourceExists = !string.IsNullOrEmpty(path) && File.Exists(path);
string libraryHash = sourceExists ? config.Identity.LibraryIdentityHash() : null; // null => skip check, trust cache (source gone)
if (File.Exists(cachePath)) {
    try {
        LibraryCache.LibraryCacheStatus status;
        var cached = LibraryCache.LoadCache(cachePath, libraryHash, out status);
        if (cached != null && cached.Count > 0) { logInfo("Loaded ... from cache"); return cached; }
        if (status == LibraryCache.LibraryCacheStatus.IdentityMismatch)
            logInfo("Library cache '...' was built from a different version of the source library; ignoring the stale cache and rebuilding from source.");
    } catch (Exception ex) { logWarning("Failed to load library cache: ...; Falling back to source."); }
}
...
LibraryCache.SaveCache(cachePath, entries, libraryHash); // non-null here: source existed to parse
```
Compute the hash once and reuse it for both read-check and save.

**`Osprey.Test/IOTest.cs`** — tests:
- Replace `TestLibraryLoaderIgnoresStaleCache` with a direct `LibraryCache` test:
  save stamped with "hash-A" → load with "hash-A" = `Loaded` + entries; load with
  "hash-B" = `IdentityMismatch` + null; load with `null` = `Loaded` (no-check path).
- Update the two round-trip `SaveCache(path, entries)` callers (`IOTest.cs:782`, `:861`)
  to pass a hash argument.
- Recommended: one end-to-end test exercising the *real* `LibraryIdentityHash` — write a
  temp library file, stamp a cache with its hash, bump the file's size/mtime, assert the
  recomputed hash no longer matches (locks size+mtime sensitivity to the actual file).

## Decisions / notes
- **Silent rebuild, not hard-abort.** Unlike `ParquetScoreCache` (which hard-aborts on a
  library mismatch, per [[feedback_hard_fail_over_warn_proceed]]), the libcache silently
  rebuilds — it is pure, reconstructable performance state; aborting would be hostile.
  Keep #4338's rebuild-and-log behavior, just driven by the identity hash.
- **Cross-impl format divergence is fine.** This makes the C# `.libcache` v2 while Rust's
  writer stays v1 (no hash). Deemed irrelevant: `maccoss/osprey` (Rust) is a historical
  parity artifact we compare *against*, not run side-by-side sharing a `--cache-dir`
  (see [[project_ospreysharp_official_rust_retired]], [[project_osprey_parity_removal_sprint]]),
  so there is no shared-cache ping-pong concern. No Rust change needed.
- **Not algorithm-affecting.** Changes cache *validity* only, not scored output, so the
  byte-parity golden is unaffected. Gate is the standard Osprey pre-commit
  (`Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`, ~30s); run
  `regression.ps1 -Dataset Stellar` as a sanity check but no divergence expected.

## Approach
After #4338 lands, branch `Skyline/work/YYYYMMDD_osprey_libcache_identity`, apply the
above, pre-commit gate, open PR crediting that it tightens #4338. Small, self-contained,
I/O-layer only.
