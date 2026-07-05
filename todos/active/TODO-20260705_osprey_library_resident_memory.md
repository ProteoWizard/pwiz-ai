# Osprey: reduce resident library memory during scoring

**Issue:** ProteoWizard/pwiz#4372
**Status:** open / not started. Split out from the #4355 memory-bounding work
(`TODO-20260703_osprey_memory_bounding.md`) on 2026-07-05.

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
