# TODO: Osprey spectra.bin v4 — end-of-file index for cheap streaming build

**Status**: Backlog (follow-up to the Stages 1–4 streaming PR).
**Priority**: Medium — makes the per-window streaming *I/O*-efficient (the streaming PR
already made it *memory*-efficient).
**Created**: 2026-07-16
**Scope**: `pwiz_tools/Osprey/Osprey.IO/SpectraCache.cs` (writer + version),
`Osprey.IO/SpectraWindowIndex.cs` (`BuildFromCache`), `Osprey.Test/IOTest.cs`.

## Motivation
The Stages 1–4 streaming PR builds the per-window streaming index
(`SpectraWindowIndex.BuildFromCache`) by **walking every MS2 record's 48-byte prefix
front-to-back**, seeking past each peak blob — because the current **V3** format has no
offset index, just front counts (`nMs2`, `nMs1`) followed by sequential variable-length
records. That walk saves **memory** and **peak-decode CPU**, but the prefixes are scattered
across the whole ~6.3 GB file, so on a **cold HDD** the disk still scans the entire file to
locate windows (and OS read-ahead pulls much of it in) — it does *not* save build-time disk
I/O. So streaming currently reads the file roughly twice on a cold HDD: the header-walk to
build the index, then per-window peak loads during scoring.

Skyline's standard cache pattern — **an index at the end of the file** — fixes this: seek to
EOF, read one compact contiguous index, build the map from it alone, then touch only the
peaks of the windows actually scored. That turns "scan 6.3 GB of scattered prefixes +
re-read scored windows" into "read ~8 MB index + read scored windows."

## What to do
- **Bump `SpectraCache.VERSION` 3 → 4.** Writer (`SaveSpectraCache`) appends an index block
  after the MS1 section holding, per MS2 record, everything `BuildFromCache` derives:
  `{ fileOffset, isoCenter, isoLower, isoUpper, rt }` (≈ 40 B × nMs2 ≈ 8 MB on Astral), plus
  the MS1 section's offset + count. Record the index's start offset in the header (or a
  trailing 8-byte pointer at EOF, the classic "index at end" locator).
- **`BuildFromCache` (v4):** seek to the index, read it, build `windowKey→offsets` +
  `AllMs2Rts` + first-cycle `IsolationWindows` + load MS1 (from the recorded MS1 offset) —
  **no record walk**. Must produce a **byte-identical** index/map to the v3 walk
  (same `windowKeysInFileOrder`, same per-key first `IsolationWindow`, same `AllMs2Rts`,
  same first-cycle windows), so streaming output stays byte-identical.
- **V3 migration decision (pick one):**
  - *Dual-read* — `BuildFromCache` branches on version (v3 → walk, v4 → end-index); no forced
    re-parse; keeps two read paths for a while. (Recommended initially — zero migration cost.)
  - *Invalidate* — `TryReadHeader` rejects < 4 → one-time re-parse + re-cache per file on
    first use (a one-time HDD cost for a large corpus; single read path afterwards).
- **`LoadSpectraCache` (full loader, Stage 6):** confirm unaffected — it reads exactly
  `nMs2 + nMs1` records and ignores the trailing index bytes.
- **Co-design with the streaming-parse lever:** a v4 writer that tracks offsets as it writes
  is a step toward *never materializing on a cache miss* either (stream mzML → write records
  → append index), so keep the writer streaming-friendly. That parser rewrite is its own
  separate lever/TODO.

## Gates
- `regression.ps1 -Dataset All` (streaming output byte-identical to golden — the map must be
  identical whether built by walk or end-index).
- A v4 round-trip unit test (write v4, `BuildFromCache`, assert the map == the v3-walk map on
  the same spectra; extend `TestSpectraWindowIndex`).
- **Cold-HDD I/O measurement** (`BuildFromCache` wall-time + bytes read, v3-walk vs
  v4-index) on a large Astral file — this is the whole justification; prove it.

## Not in scope
- Stage-6 rescore streaming (separate TODO
  `TODO-osprey_stage6_rescore_spectra_streaming.md`).
- The streaming mzML→cache writer that avoids materializing on a cache *miss* (separate lever).
