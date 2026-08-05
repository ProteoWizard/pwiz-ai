# TODO-20260530_ospreysharp_remove_blibqvalues_diag.md -- Remove the orphaned OSPREY_DUMP_BLIB_QVALUES diagnostic

## Status

**Completed** -- PR [#4253](https://github.com/ProteoWizard/pwiz/pull/4253)
merged 2026-05-31 as `9eee47851f`. Small follow-up to #4252 (the
WriteBlibOutput decomposition), actioning the self-review's follow-up
question.

### 2026-05-31 - Merged

PR #4253 merged to `master` as `9eee47851f`; all CI green, zero
failures. Review chain clean (Copilot 0 comments; fresh-context
self-review clean, no findings). Removed the orphaned
`OSPREY_DUMP_BLIB_QVALUES` diagnostic (`MaybeDumpBlibQValues` + its
call), re-syncing C# with the Rust side, which had already dropped its
half. Parity gate intentionally skipped (env-gated-off, unreachable
code -> normal output provably unchanged); build + tests + inspection
were the appropriate gate. Nothing deferred.

## Branch Information

- **pwiz branch**: `Skyline/work/20260530_ospreysharp_remove_blibqvalues_diag`
  (off `master` @ 293d3d4724)
- **ai branch**: `master`

## Background

`OSPREY_DUMP_BLIB_QVALUES` (the `MaybeDumpBlibQValues` helper in
`MergeNodeTask`, extracted in #4252) was an env-gated cross-impl dump
added to bisect a C#-vs-Rust experiment-peptide q-value drift in the
blib write. It is self-marked *"Temporary -- remove once peptide-q
drift is bisected and fixed."*

That drift is **resolved** (confirmed by Brendan). A Rust-side audit
settles intent:

- The broad `OSPREY_DUMP_*` / `OSPREY_DIAG_*` diagnostics subsystem is
  INTENTIONAL and maintained on both sides (Rust `crates/osprey/src/
  diagnostics.rs` + `osprey-fdr` dumps, mirrored by C#
  `OspreyDiagnostics.cs`) -- the steel-thread cross-impl bisection
  toolkit. KEEP.
- `OSPREY_DUMP_BLIB_QVALUES` is the lone outlier: ad-hoc inline (never
  in the organized module), self-marked temporary, and **has no Rust
  counterpart** -- grep of the whole Rust tree for `BLIB_QVALUES` /
  `blib_qvalues` returns nothing. The Rust side already removed its half;
  C# was the un-cleaned remainder.

Audit of all C#-only `OSPREY_*` switches (66 C#, 67 Rust) -- the other
five C#-only tokens (`OSPREY_LOAD_CALIBRATION`, `OSPREY_MAX_PARALLEL_FILES`,
`OSPREY_MAX_SCORING_WINDOWS`, `OSPREY_TEST_BASE_DIR`, and an
`OSPREY_MAX_SCORING_` partial-match artifact) are FUNCTIONAL knobs
(calibration load, parallelism/window limits, test root), not diagnostic
leftovers. So `OSPREY_DUMP_BLIB_QVALUES` is the only orphan.

## What shipped

- Deleted the `MaybeDumpBlibQValues` helper and its single orchestrator
  call from `MergeNodeTask.WriteBlibOutput`. No other change.

## Verification

- Build clean (net472 + net8.0); 345/347 tests; inspection 0/0
  (no using became redundant -- System.IO / Globalization / StringComparer
  all still used elsewhere in the file).
- **Cross-impl parity gate intentionally NOT run.** The removed code is
  env-gated (`OSPREY_DUMP_BLIB_QVALUES != "1"` returns immediately) and
  off by default; the `-SkipRust` gate never sets that var, so the path
  was unreachable under the gate and normal blib output is provably
  unchanged. Build + unit tests + inspection are the appropriate gate
  for deleting unreachable env-gated code. (Per memory
  `feedback_ospreysharp_csharp_regression_gate` -- verify what matters,
  don't burn cycles re-confirming the logically guaranteed.)

## Related

- #4252 (decomposition; source of the self-review follow-up)
- Rust `crates/osprey/src/diagnostics.rs` (the intentional subsystem,
  for contrast)
- Memory: `feedback_ospreysharp_csharp_regression_gate`
