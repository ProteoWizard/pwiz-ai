# Osprey: reduce resident library memory during scoring

**Issue:** ProteoWizard/pwiz#4372
**Branch:** `Skyline/work/20260706_osprey_library_resident_memory` (off master `174e3ddd8`)
**PR:** [#4381](https://github.com/ProteoWizard/pwiz/pull/4381)
**Status:** in review. Split out from the #4355 memory-bounding work
(`TODO-20260703_osprey_memory_bounding.md`) on 2026-07-05.

## Plan (approved 2026-07-06)

First PR = **struct-ify the resident fragment representation** (highest-leverage,
output-preserving lever). The resident cost is a pointer-chased managed object graph:
`LibraryEntry.Fragments` held `List<LibraryFragment>` where BOTH `LibraryFragment` and
`FragmentAnnotation` were **classes** (2+ heap objects + ~16 B header each per fragment;
tens of millions of tiny objects at 3.17M entries). Rust holds the same data as value
structs (contiguous, header-free) - so this is C#-first work to match Rust's memory
model, constrained only by the byte-identical regression gate (not cross-impl parity;
Rust has not done a library-residency reduction either).

Deferred to follow-ups (measured, revertible): drop/replace the `_libraryById` parallel
index (~50-150 MB); load-time string interning (measure - #4355 reverted interning as
net-negative on the concurrent path); convert `Fragments` to `LibraryFragment[]`; the
16-24 B fragment squeeze. mmap / precursor-window paging is out (full-library-per-window
scan would thrash; no m/z index).

## Progress

- 2026-07-06: **Phase 1 implemented.** `LibraryFragment` + `FragmentAnnotation` class ->
  value struct; the per-fragment `NeutralLoss` heap reference collapsed to a
  `NeutralLossCode` byte enum + inline `CustomLossMass` double (masses preserved via a
  static `NeutralLoss` helper). `Fragments` kept as `List<LibraryFragment>` for a minimal
  diff (backing array is now contiguous/blittable - captures the multi-GB win; leaves only
  ~127 MB of List wrappers). `.libcache` on-disk format byte-unchanged (VERSION stays 2;
  the 1e-6 Custom->named tag collapse preserved). 10 files changed. The one in-place
  mutation (BlibLoader intensity normalize) rewritten as index write-back. All fragment
  construction sites already set `Charge` explicitly; ScoringTest fixtures pinned to
  `Charge = 1` to preserve the old class-ctor default.
- 2026-07-06: **Gates:** Debug build green (net472 + net8.0); Osprey.Test 453/453 pass
  (3 skipped) incl. the IOTest libcache round-trip (format gate); ReSharper inspection
  clean on changed files (9 remaining are pre-existing `SystemMemory.cs` warnings on
  master, not this change). `regression.ps1 -Dataset Stellar` (byte-identical mode1/2/3)
  running.
- 2026-07-06/07: **Added string interning** (`LibraryStringInterner`, `OSPREY_NO_INTERN`
  toggle) + a post-GC `[MEM library-resident]` managed-heap probe in `PerFileScoringTask`.
  Debug build + 453 tests + ReSharper clean (0 issues).

## Measured results (8-file Astral SEA-AD Carafe, clean wiped work-dir)

Method: each run in a fresh, wiped `--work-dir` (no stale `.libcache`/`.spectra.bin`/
`.calibration.json`/scores parquet to skip work); memory sampled EXTERNALLY (process WS
poll) plus a post-full-GC `GC.GetTotalMemory(true)` probe right after library load.
Binaries snapshotted (baseline master `174e3ddd8` vs branch) so runs are checkout-independent.

**True resident library (managed heap, post-GC):**
- struct + interning: **3.20 GB**
- struct, no interning (`OSPREY_NO_INTERN=1`): **3.41 GB**  -> interning = **-0.21 GB (~6%)**
- fragment structs alone: **~1.5 GB** (WS floor 10.8 -> 9.3 GB; managed-heap delta consistent)
- original (class fragments, no interning), inferred: **~4.9 GB** -> now **3.20 GB (~35% smaller)**

**BIG REFRAME:** the resident library is **~3-5 GB, NOT ~18-20 GB.** The 18-20 GB figure
was *working set*, inflated by the one-time **5.3 GB TSV read buffer** (+ libcache write +
GC slack) during load, which the forced-GC probe strips out. In the full 8-file run the
library is ~3.4 GB of an **~80 GB peak**; the peak is **stage6 reconciliation (#4376)** and
the scoring plateau (~65 GB) is the per-file transient + FdrEntry accumulation
(**#4355/#4378**). So #4372 is a **small lever**; the memory that actually gates 100s of
files lives in #4376 and #4355/#4378.

**Perf (n=1, 8-file):** all stage walls slightly faster (total 1866 -> 1792 s, ~4%);
library load ~9% faster (fewer allocations). Peak private bytes 91.4 -> 85.0 GB (-6.4 GB).

**Byte-identical:** Stellar `regression.ps1` mode1/2/3 (fragment structs) PASS. 8-file Astral
before/after blibs identical except the random blib LSID GUID (x2) + creation timestamp
(62 of 69,566,464 bytes; per-run metadata, not code).

**Decision (2026-07-07):** keep interning (free, byte-identical, +0.21 GB). Finalize #4372
= fragment structs + interning; further library micro-opts have diminishing returns
(library is ~3 GB). Next real memory lever: **#4376** (reconciliation, the ~80 GB peak).

**PR narrative point:** interning's benefit **scales up sharply with PTM-heavy libraries**.
PTMs explode the entry count (many modforms per peptide) but NOT the distinct-string
count -- the stripped sequence, protein IDs, and gene names are identical across all
modforms, and mod names ("Phospho", "Oxidation", ...) are a few dozen distinct values
referenced by millions of entries. So the collapse ratio climbs well above the 50.4%
measured on the (PTM-light) Carafe library, and interning reclaims proportionally more
exactly where libraries get largest. The fragment-struct win scales similarly (more
modforms -> more fragment arrays). Reconciliation peak note: the ~80 GB is WORKING SET on
a 94 GB box with lazy Server GC; #4378 measured managed heap ~31-47 GB vs ~79 GB WS, so
the true reconciliation footprint is likely well under 80 GB -- MEASURE the post-GC
managed heap at stage6 (on a build with #4378) before sizing #4376.

## Problem

Osprey holds the full **target+decoy spectral library resident** in memory across
per-file scoring. For a large library (the **3.17M-entry Carafe library**) that is
roughly **~18-20 GB resident**, which drives the scoring working-set to **~57 GB**.

This is the memory **floor** that the #4355 first-pass-FDR minimal-projection work
does *not* address. #4355 reduces the *join* peak below the scoring plateau, so on the
real dataset the library/scoring plateau is now the ceiling. They are **independent
levers** — this TODO owns the library/scoring side.

## Evidence (from the #4355 validation run)

40-file Astral SEA-AD DIA search vs the 3.17M-entry Carafe library, `OSPREY_LOG_MEMORY=1`,
projection path (`OSPREY_FDR_PROJECTION=1`, step b iii), sequential:
- `[MEM scored file 1/40]` managed_heap **26.5 GB** (mostly library), working_set 34.9 GB.
- Scoring plateau is BOUNDED/flat per file (step (a) works) but sits at **~50-60 GB WS**,
  ~40 GB peak managed_heap, ~60 GB peak_paged.
- Library cache: `carafe_spectral_library.tsv.libcache`, 3,167,462 entries; TSV 5.3 GB.
- (Numbers to be firmed up when the 40-file run completes; slope extrapolated to 82/400/1500.)

## Why it matters

300-1500 files are the common scale; the target is a **modest machine** (64 GB or less).
With the join handled by #4355, the library resident cost is what keeps a large search
off a modest box. Also relevant: the library is loaded once but is ~O(library size), so it
does NOT shrink with the projection work.

## Candidate approaches (to investigate)

- **Memory-map the `.libcache`** instead of loading all entries fully resident (page in
  the windows a scoring pass needs).
- **Stream/page** library entries by precursor window / RT so only the active slice is resident.
- **Avoid holding the full target+decoy set resident** — e.g. generate/pair decoys on demand
  rather than materializing all 3.17M target+decoy entries.
- Trim per-entry fields; columnar / SoA library storage; drop fields not needed after indexing.
- Confirm what fraction of the ~18-20 GB is fragment arrays vs metadata (guides which lever).

## Gates

Same discipline as #4355: `regression.ps1 -Dataset Stellar` byte-identical (mode1/2/3, 1e-9)
+ `Test-PerfGate.ps1` (a memory-map/paging change is exactly the kind that can slow scoring).
Validate the actual reduction on a real large-library run with `OSPREY_LOG_MEMORY`.

## Relationship

- #4355 (`TODO-20260703_osprey_memory_bounding.md`): first-pass-FDR minimal-projection join.
  Reduces the join peak; this TODO reduces the scoring/library floor. Independent.
