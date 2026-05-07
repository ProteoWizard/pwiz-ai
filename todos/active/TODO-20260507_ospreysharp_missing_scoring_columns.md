# TODO: OspreySharp missing scoring path columns (6 allowlisted in Stage 6 parity harness)

**Status**: Active
**Branch**: `Skyline/work/20260507_ospreysharp_missing_scoring_columns`
**Priority**: Medium (Stage 7 second-pass Percolator can proceed without these; downstream consumers like Skyline blib output benefit from them being populated)
**Complexity**: Medium (data exists in C# at scoring time; need to plumb through `FdrEntry` and the `WriteScoresParquet(FdrEntry)` overload)
**Created**: 2026-05-06
**Started**: 2026-05-07
**Scope**: `C:\proj\pwiz\pwiz_tools\OspreySharp\` (OspreySharp port, C#)
**Predecessor**: `ai/todos/completed/TODO-20260429_osprey_sharp_stage6.md` — Stage 6 cross-impl byte-parity landed end-to-end on Stellar + Astral with these six columns in the harness allowlist (squash-merged as ProteoWizard/pwiz#4187 commit `a0f784deb`).

## Motivation

`Compare-Stage6-Crossimpl.ps1`'s `Diff-Parquet` step compares the
reconciled per-file `.scores.parquet` files between Rust osprey and
the OspreySharp port. Six columns are in an allowlist (expected to
diverge) because OspreySharp's scoring path doesn't yet write them:

| Column | Type | Role |
|---|---|---|
| `fragment_mzs` | `byte[]` (f64 LE blob) | Library fragment m/z list for the entry |
| `fragment_intensities` | `byte[]` (f32 LE blob) | Library fragment relative intensities |
| `reference_xic_rts` | `byte[]` (f64 LE blob) | RT axis of the reference XIC across `[peak.start_index..=peak.end_index]` |
| `reference_xic_intensities` | `byte[]` (f64 LE blob) | Reference XIC intensities, same range |
| `bounds_area` | `double` | Peak area integrated within the **reconciled** boundary (distinct from `peak_area` which is the original CWT peak's area) |
| `bounds_snr` | `double` | Peak SNR within the reconciled boundary (distinct from `signal_to_noise`) |

These six are populated by Rust in `compute_features_at_peak`
(`crates/osprey/src/pipeline.rs:6595-6620`). They flow through the
Rust `CoelutionScoredEntry` into the parquet write path. Skyline's
blib export and any downstream tooling that wants per-precursor
fragment evidence needs them.

In OspreySharp, the data exists at scoring time:

- `entry.Fragments` — the library fragment list (mz, relative_intensity)
- `xics[refXicIdx]` — the reference XIC (rts, intensities)
- the reconciled `peak` — start/apex/end indices for slicing the XIC
- `bounds_area` / `bounds_snr` — already computed in `BuildOverridePeaks`
  and the post-rank apex recompute, just not stored back on `FdrEntry`

The gap is purely plumbing: carry these from the scoring functions
through `FdrEntry` to `ParquetScoreCache.WriteScoresParquet`'s
`FdrEntry`-overload, which today writes them as null/zero.

## Scope

1. **Extend `FdrEntry`** with the six fields:

   ```csharp
   public double[] FragmentMzs { get; set; }            // null when not populated
   public float[]  FragmentIntensities { get; set; }
   public double[] ReferenceXicRts { get; set; }
   public double[] ReferenceXicIntensities { get; set; }
   public double   BoundsArea { get; set; }
   public double   BoundsSnr { get; set; }
   ```

   Match Rust's `CoelutionScoredEntry` field shapes byte-for-byte so
   the parquet blob layout matches.

2. **Populate at scoring time** in `AnalysisPipeline.ScoreCandidate`
   (and the gap-fill paths in `RunCoelutionScoring`):

   - `FragmentMzs` / `FragmentIntensities`: `entry.Fragments.Select(f
     => f.Mz/RelativeIntensity).ToArray()`
   - `ReferenceXicRts` / `ReferenceXicIntensities`:
     `xics[refXicIdx].RetentionTimes[bestPeak.StartIndex..=bestPeak.EndIndex]`
     (and same for intensities)
   - `BoundsArea` / `BoundsSnr`: already computed for the reconciled
     peak — assign instead of discarding

3. **Wire through the parquet writer** at
   `pwiz_tools/OspreySharp/OspreySharp.IO/ParquetScoreCache.cs`. The
   `FdrEntry`-overload of `WriteScoresParquet` currently writes these
   columns as null/zero; populate them from the new `FdrEntry`
   fields. Match Rust's binary blob layout (verify via
   `Compare-Stage6-Crossimpl.ps1` after).

4. **Remove the allowlist** in
   `ai/scripts/OspreySharp/Compare-Stage6-Crossimpl.ps1` (the
   `$expectedDiff` array) once parity is proven. End-to-end the
   harness should pass with `0 allowlisted diff column(s)`.

## Validation

- `Compare-Stage6-Crossimpl.ps1 -Dataset Stellar` PASSes with the
  empty allowlist (`$expectedDiff = @()`). All 12 pre-existing
  columns continue to PASS.
- Same on Astral.
- `OspreySharp.Test` round-trip tests (`TestParquetScoreCacheRoundTrip`)
  cover the new fields.

## Notes

- `bounds_area` vs `peak_area`: the difference matters when the
  reconciled boundary differs from the original CWT peak's boundary
  (which is the common case for `ForcedIntegration` reconciliation
  actions). Don't conflate the two.
- The blob column layout (per-row byte array of f64/f32 LE values)
  needs to match Rust's exact byte-for-byte serialization for the
  Diff-Parquet harness to pass at numeric tolerance 1e-6.
- After this lands, Stage 6 can be flipped to "fully done" without
  caveats; the harness's allowlist arg becomes optional rather than
  required.

## See also

- `ai/todos/active/TODO-20260429_osprey_sharp_stage6.md` — Session 10
  closeout where these six columns were enumerated and validation
  ran with them allowlisted.
- `crates/osprey/src/pipeline.rs:6595-6620` (Rust source of truth
  for the field shapes).
- `pwiz_tools/OspreySharp/OspreySharp.IO/ParquetScoreCache.cs` —
  parquet writer that currently zeros the columns.
