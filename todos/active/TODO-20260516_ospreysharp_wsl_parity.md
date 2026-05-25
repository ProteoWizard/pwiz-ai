# TODO-20260516_ospreysharp_wsl_parity.md — Phase 2 (systematic cross-impl bisection)

## Phase History

The sprint began as a WSL parity + perf optimization push in mid-May.
After three days of tooling, Rust HPC chain bug hunts (Bugs A through D),
and porting the same fixes to C#, Test-Regression was reporting `PASS` on
Stellar but boundaries still drifted at 1e-9 between Rust and C#. That
drift became the focus of Phase 2.

- **Phase 1** (2026-05-17 → 2026-05-19 afternoon): WSL setup, perf
  measurement, Rust + C# bug fixes, build-out of diagnostic tooling.
  See [TODO-20260516_ospreysharp_wsl_parity-phase1.md](TODO-20260516_ospreysharp_wsl_parity-phase1.md).
- **Phase 2** (2026-05-19 evening → present, this file): end-to-end
  Pass-1 bisection driver pinpointed Stage 3 calibration as the first
  divergence; the work since has been a deep cal_match / LDA / xcorr
  bisection that landed an iso_upper f64 cvParam fix, F10 → F17 dump
  precision fixes, a per-side Test-Regression refactor, and (today) the
  Rust half of the coordinated f64 calibration flip.

## Branch Information

- **pwiz branch**: `Skyline/work/20260516_ospreysharp_wsl_parity`
  (PR [#4233](https://github.com/ProteoWizard/pwiz/pull/4233) open)
- **osprey branch**: `fix/hpc-chain-stage7-second-pass-percolator`
  (PR [#37](https://github.com/maccoss/osprey/pull/37) open)
- **ai branch**: `master`

## Phase 2 Objective

Bring Stage 3 calibration cal_match to bit-equal (or f64-epsilon)
cross-impl on Stellar Single under the per-side gate definition, then
verify Stage 5 percolator passes at 1e-9 with each side feeding its own
Stage 4 outputs forward.

Stage 4 main-search f32-cascade features (`xcorr`, `sg_weighted_xcorr`)
are off-limits per user guidance; they remain at f32 magnitude
(~1e-6 / ~1e-7) and Stage 5 must tolerate them. `rt_deviation` cascades
from the LOESS calibration model and should align once calibration
inputs align cross-impl.

## Quick Reference

**Test harnesses:**

- Stage 1-4 strict per-side parity:
  `pwsh -File ./ai/scripts/OspreySharp/Compare-Stage1to4-Strict.ps1 -Dataset Stellar -Files Single -Force`
- Full HPC chain regression (per-side):
  `pwsh -File ./ai/scripts/OspreySharp/Test-Regression.ps1`
- End-to-end Pass-1 boundary walker:
  `pwsh -File ./ai/scripts/OspreySharp/Compare-EndToEnd-Bisect-Crossimpl.ps1`
- Per-column cal_match max-diff:
  `python C:\proj\ai\.tmp\cal_match_per_col_diff.py`

**Build wrappers:**

- Rust: `pwsh -File ./ai/scripts/OspreySharp/Build-OspreyRust.ps1 -Fmt -Clippy -RunTests`
- C#: `pwsh -File C:/proj/ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunInspection -RunTests`

**Test data:**

- Stellar Single test root: `D:\test\osprey-runs\stellar\`
- Stellar 3-file: same root, different subdir per harness

**Key file pointers:**

- Rust scorer.xcorr() (now f64 inline): `crates/osprey-scoring/src/lib.rs:2076-2178`
- Rust XcorrScratch pool (still f32 fields): `crates/osprey-scoring/src/xcorr_pool.rs`
- C# calibration apex xcorr (uses f32 cache path): `pwiz_tools/OspreySharp/OspreySharp/Tasks/PerFileScoringTask.cs:2275`
- C# XcorrScratchPool (dual-track f64+f32 ready): `pwiz_tools/OspreySharp/OspreySharp.Scoring/XcorrScratchPool.cs`
- C# SpectralScorer (both XcorrAtScan f64 and XcorrFromPreprocessed f32 paths): `pwiz_tools/OspreySharp/OspreySharp.Scoring/SpectralScorer.cs:92,125,171,226,280,303,508`

## Current Status (2026-05-20 evening) — sprint complete

**Cross-impl Stage 1-4 parity reached the architectural floor on both
build targets.** The .NET 8.0 result is the proof: when we swap the
.NET Framework 4.7.2 build for the .NET 8.0 build of OspreySharp,
nearly every remaining drift collapses to bit-equal or 1-2 ULP f64
reduction-order noise. The remaining drift on net472 is therefore not
algorithmic divergence we should chase further — it is the .NET
Framework parser limitation, fixed in .NET 5+'s Eisel-Lemire parser.

**Stellar Single boundary results, side-by-side:**

| Boundary | net472 | net8.0 |
|---|---|---|
| CAL_SAMPLE rust_cal_sample.txt | PASS | PASS |
| CAL_SAMPLE rust_cal_scalars.txt | PASS | PASS |
| CAL_SAMPLE rust_cal_grid.txt | PASS | PASS |
| CAL_WINDOWS | PASS | PASS |
| CAL_MATCH | 3.55e-15 (137 apex_rt rows at parser ULP) | **6.94e-18 sub-ε** |
| LDA_SCORES | 4.84e-14 | 4.84e-14 (real f64 cascade) |
| LOESS_INPUT | PASS | PASS |
| CAL_JSON | 4.71e-12 | **4.44e-16** (n_above_1e-15=0) |
| SCORES_PQ Stage 4 | 8+ columns drifting (parser-cascaded) | only sg_weighted_cosine + median_polish_residual_correlation at 1-2 ULP |

**Stage 4 .scores.parquet on net8.0**: apex_rt, peak_apex, peak_area,
peak_sharpness, rt_deviation, bounds_area, xcorr, sg_weighted_xcorr
— all bit-equal. The two remaining columns differ at 1-2 ULP from
genuine f64 reduction-order noise (weighted cosine sum,
median-polish correlation sum).

**Verification commands:**
```
# net472 (canonical Skyline distribution):
pwsh -File ./ai/scripts/OspreySharp/Compare-Stage1to4-Strict.ps1 -Dataset Stellar -Files Single -Force

# net8.0 (proves remaining net472 drift is .NET Framework parser):
pwsh -File ./ai/scripts/OspreySharp/Compare-Stage1to4-Strict.ps1 -Dataset Stellar -Files Single -Force -Framework net8.0
```

**Why the .NET 8.0 result is the proof, not just "another data point":**

On net472 we hit 8+ columns of drift across CAL_MATCH and Stage 4 that
looked like real algorithmic divergence — apex_rt 137 rows at 2 ULP,
peak_sharpness 1216 rows at 1e-6 ("f32 cascade"), rt_deviation 460K
rows at f64 epsilon (allegedly "LOESS f64 cascade"), etc. Each looked
like a separate root cause needing focused debugging.

Swapping the same binary tree to the net8.0 build collapses ALL of
them to bit-equal except the two genuine f64-reduction-order columns.
Same source code. Same algorithms. Same inputs. Only the runtime's
double parser changed. That means the entire chain of "cascades" was
downstream of one .NET Framework 4.7.2 parser ULP — apex_rt parsed
differently → peak boundary indices selected differently → peak shape
features computed over slightly different ranges → "f32 magnitude"
drift across many columns.

So the remaining net472 FAILs are not unfinished work. They are the
known limitation of the canonical Skyline distribution's runtime.
Future investigation should reach for `-Framework net8.0` first to
confirm whether a divergence is real before chasing it.

## Progress Log (Phase 2)

## 2026-05-19 evening (late) — end-to-end Pass-1 bisection driver + Stage 4 verification

Built `ai/scripts/OspreySharp/Compare-EndToEnd-Bisect-Crossimpl.ps1`
(Pass 1 driver, walks all natural boundary outputs in stage order:
calibration.json → reconciliation.json → 1st-pass.fdr_scores.bin →
reconciled scores.parquet → 2nd-pass.fdr_scores.bin → Stage 7
protein FDR dump → blib) and ran Stellar 3-file.

### Pass 1 result: every boundary FAILed

All 17 boundary comparisons failed at 1e-9 tolerance — divergence
starts at the very first stage compared (Stage 3 calibration.json).

### Stage 3 calibration.json: REAL numeric divergence, not just formatter

Wrote `ai/.tmp/json_tol_diff.py` to walk both JSONs and report
per-leaf max_abs_diff. Result: not formatter-only.

| Leaf | Rust | C# | Diff |
|---|---|---|---|
| `ms1_calibration.count` | 18 | 193 | 10x more candidates on C# |
| `ms1_calibration.adjusted_tolerance` | 0.00135 | 0.01325 | ~10x |
| `ms1_calibration.mean` | -1.9e-5 | -5.1e-4 | 27x |
| `ms1_calibration.sd` | 4.4e-4 | 4.2e-3 | ~10x |
| `rt_calibration.model_params.abs_residuals[5]/[6]` | swapped | swapped | order-only |

C# also DOES NOT write `metadata.isolation_scheme`,
`ms1_calibration.histogram`, `ms2_calibration.histogram`,
`metadata.num_sampled_precursors`, `metadata.num_confident_peptides`
(those are diagnostic-only metadata gaps, not load-bearing).
5,285 of 22,105 numeric leaves diverge above 1e-9.

### Stage 4 verification: PIN features FAIL at 1e-9 cross-impl in end-to-end mode

Wrote `ai/.tmp/stage4_check.ps1` — fresh `--no-join` per side
+ `parquet_diff.py --tolerance 1e-9` on each per-file
`.scores.parquet`. Stellar 3-file:

```
[rust] --no-join exit=0 wall=01:28
[cs]   --no-join exit=0 wall=01:32

per-column [DIFF] (file 20):
  xcorr               max_diff=1.08e-1  n_diverg=417487/462802  (~90% of rows)
  sg_weighted_xcorr   max_diff=1.72e-2  n_diverg=416130
  peak_sharpness      max_diff=9.49e+4  n_diverg=706
  cwt_candidates      n_diverg=9717     (binary blob ULP differences)
  apex_rt             diff=0.061 min    (row [0] catastrophic)
  peak_apex           diff=213          (row [0] catastrophic)
  sg_weighted_cosine  diff=0.057        (row [0] catastrophic)
  ... most other features: 1 row differs (row [0])
```

Files 21 + 22 have ONLY bulk drift, no row-[0] catastrophic:
- xcorr max ~5e-7 / sg_weighted_xcorr max ~4e-7 on ~417K rows each
- peak_sharpness max 6e-7 on ~700 rows

So Stage 4 has TWO distinct divergence phenomena:

1. **Bulk f32-magnitude drift** on xcorr / sg_weighted_xcorr (~5e-7
   on ~90% of rows on every file). Workflow doc claimed Stellar
   `--resolution unit` is "not affected by the f32 scratch path"
   — that statement may no longer hold, or there is a regression
   in the unit-resolution xcorr code path.

2. **One catastrophic peak-pick divergence** at file 20 entry_id 0
   (apex_rt diff 0.061 min, peak_apex diff 213, sg_weighted_cosine
   diff 0.057). Likely the source of the 14-unit Stage 7 score
   divergence on SCAF8_HUMAN observed yesterday.

### The non-determinism concern

Workflow doc (status 2026-05-09): "Stages 1-4 PIN features bit-
identical at ULP on Stellar (466K entries, all 21 features under
1e-10)". Today's run with the current binaries shows 5e-7 drift on
~90% of rows. Either:

- (A) The Rust Bug A/B/C/D fixes from earlier today, or the C#
  fixes from yesterday afternoon, changed Stage 4 behavior. Need
  git-history bisection to confirm.
- (B) Test-Regression's `stage1to4` gate has been passing because
  its stage-isolation setup masks the drift we see in pure
  end-to-end `--no-join` mode. Need to read Test-Regression more
  carefully to understand the comparison setup.

User signed off at this point — frustration with apparent
non-determinism across sessions. Tomorrow's pivot: have the
session walk the user through reproducing these results manually
so they can pause and inspect in Visual Studio rather than
relying on the agent's interpretations.

## 2026-05-20 morning — root cause of "non-determinism" + new gate definition

### Why prior sessions claimed "stage1to4 PASS" honestly

The mystery was resolved on inspection of `Test-Regression.ps1`:
the stage1to4 gate calls
`inspect_parquet.py --diff --tolerance 1e-6` (line 568). My new
end-to-end driver and `stage4_check.ps1` ran `parquet_diff.py
--tolerance 1e-9` (~1000x tighter). The cross-impl xcorr drift
we measured (~5e-7) cleanly passes 1e-6 but fails 1e-9 — both
prior reports of PASS were accurate at the gate's measured
tolerance.

The workflow doc's "21/21 features under 1e-10" claim is
inconsistent with what the gate actually measures; that doc
statement appears to have been overstated or measured under
different conditions than today's binaries. The verifier that's
actually in the regression suite is gated at 1e-6.

### Test-Regression confirmation today (Stellar Single)

`Test-Regression.ps1 -Dataset Stellar -Files Single` PASSes all
five gates with current binaries (after the `OspreySharp.VERSION`
bump from 26.6.0 → 26.6.1; see "Version drift" below). The blib
gate found ONE row of `OspreyMetadata.Value` differing on
`osprey_version` (rust=26.6.1, cs=26.6.0) before the bump;
every scientific column in the blib (`RefSpectra`,
`RefSpectraPeaks`, `Modifications`, `Proteins`,
`RetentionTimes`, `OspreyExperimentScores`, `OspreyRunScores`,
`OspreyPeakBoundaries`) was bit-equal at max_diff=0.000e+000.
Wall times Stellar Single (each side): stage1to4 0:29-0:32,
stage5 0:59-1:21, stage6 1:24-1:47, stage7 0:11-0:13, blib
0:14-0:16.

### Version drift root cause (Mike's commits since v26.6.0)

`git log` on `maccoss/osprey`:
- 2026-05-13 19:36 — Mike: v26.6.0 release
- 2026-05-14 23:26 — Mike: "Fixed reconciliation to pair
  library-supplied decoys by base_id" — the algorithmic substance
  of 26.6.1, only affects `--decoys-in-library` mode (not Stellar)
- 2026-05-15 06:41 — Mike: v26.6.1 release
- 2026-05-17 10:23 — Mike: "Add test for manifest recovering decoys"

Mike pushes directly to main (no PRs). User is requesting Mike
move to PR-based workflow during critical sprint windows so
version bumps don't silently land mid-sprint.

OspreySharp `Program.cs:41` `VERSION = "26.6.0"` bumped to
`"26.6.1"` with a TODO comment noting the algorithmic v26.6.1
fix (base_id pairing for library-supplied decoys in
`compute_consensus_rts` + `plan_reconciliation`) is NOT yet
ported on the C# side. Stellar runs in reverse-decoy mode so
the missing fix has no effect there; will affect
`AstralLibraryDecoy` (library-supplied decoys via FDRBench).

### Snappy compression cleanup

Per user direction, removed all `[Ss]nappy` mentions from the
test scripts. OspreySharp has had ZSTD support for a long time;
the snappy flag was vestigial. Files touched (functional + comment
cleanup):

- `Test-Features.ps1` — removed `--parquet-compression snappy`
  from Rust invocation
- `Compare-Stage6-Crossimpl.ps1` — removed conditional
  `--parquet-compression snappy` for Rust
- `Build-Stage6Fixture.ps1` — comment updates
- `Compare-Stage7-Rehydration-Strict-CSharp.ps1` — comment update
- `Generate-AllScoresParquet.ps1` — comment cleanup
- `ai/.tmp/stage4_check.ps1` — removed `--parquet-compression
  snappy` flag (the one I added yesterday; explained the surprising
  ZSTD-vs-SNAPPY observation in this morning's analysis)

### Stage 1-4 strict ULP comparison

New comparator: `ai/scripts/OspreySharp/Compare-Stage1to4-Strict.ps1`.
Runs `--no-join` per side with all Stage 1-3 calibration dumps
enabled and compares every output at strict tolerance (SHA-first,
then numeric-tolerance fallback). Companion:
`json_tol_diff.py` (tolerance-based JSON diff for calibration.json).

Stellar Single results (post version bump, BEFORE iso_upper fix):

| Boundary | Result | Magnitude |
|---|---|---|
| CAL_SAMPLE rust_cal_sample.txt | PASS bit-equal | 0 |
| CAL_SAMPLE rust_cal_scalars.txt | FAIL | 5 diffs at max 5.1e-13 |
| CAL_SAMPLE rust_cal_grid.txt | PASS bit-equal | 0 |
| CAL_WINDOWS rust_cal_windows.txt | FAIL | 1,732 diffs at 3.1e-5 |
| CAL_MATCH rust_cal_match.txt | FAIL | 15,833 diffs at 5.2e-10 |
| LDA_SCORES rust_lda_scores.txt | FAIL | 17 diffs at 1.0e-10 |
| LOESS_INPUT rust_loess_input.txt | FAIL | structural — 6,400 vs 7,363 rows |
| CAL_JSON | FAIL | full cascade |
| SCORES_PQ (--tolerance 0) | FAIL | most cols 1-2 ULP; xcorr/sg_weighted_xcorr ~5e-7 bulk + 1 catastrophic row |

### Root cause of CAL_WINDOWS divergence: mzdata 0.63 f32 quantization

mzdata 0.63's reader pipes isolation window cvParams through
`param.to_f32()` (reader.rs:281). At m/z 500 the f32 ULP is ~6e-5.
The Stellar mzML's `<isolationWindow>` cvParams have one specific
window (out of 125) whose upper edge in XML text lands between
two f32-representable values; on round-trip Rust gets 512.481934
while OspreySharp's f64 parse gets 512.481903 (~3e-5 m/z drift).

Fixed in osprey commit `1fe4ff7` on
`fix/hpc-chain-stage7-second-pass-percolator` branch: added a
one-pass streaming quick-xml scan in `osprey-io::mzml::parser`
that pre-extracts isolation cvParams as f64 and overrides
mzdata's quantized values at both MS2 parsing sites
(`convert_spectrum` and `load_all_spectra`). The fix is local to
osprey-io and self-contained; can be deleted in one commit when
mzdata moves to f64 storage upstream.

After the fix: CAL_WINDOWS PASSes bit-equal. Surprising downstream
effect: Stage 4 `.scores.parquet` row diffs went UP (xcorr
417,487→456,609 rows). This is because the pre-fix run had
"coincidental" cross-impl agreement on 124 of 125 windows where
f32 happened to equal f64; the fix removes that coincidence and
exposes the bulk drift that always existed (still ~5e-7 magnitude,
just spread across more rows). Max abs diffs are unchanged from
pre-fix — the algorithmic divergence sources are the same; the
fix only addressed isolation window f32 quantization, not the
xcorr-level f32 quantization elsewhere.

### Remaining Stage 1-4 strict-comparison divergences (post iso_upper fix)

| Boundary | Magnitude | Class |
|---|---|---|
| CAL_SAMPLE rust_cal_scalars.txt | 5 diffs at 5.1e-13 | ~10 ULP at m/z 400 (numerical noise) |
| CAL_MATCH apex_rt | 15,739 rows, all at exactly ~1e-10 | systematic f64 offset, C# > Rust |
| LDA_SCORES | 17 rows at 1e-10 | likely cascade from apex_rt |
| LOESS_INPUT | 6,400 vs 7,363 rows | q-value gate flip from upstream noise |
| Stage 4 xcorr / sg_weighted_xcorr | ~5e-7 bulk + 1 catastrophic row | independent f32-magnitude source elsewhere |

`apex_rt` systematic ~1e-10 offset: both sides take
`spec.retention_time` from the apex spectrum. The Stellar mzML
stores scan start time in `unitName="minute"` (e.g.,
`value="8.719852510583"`) so no ÷60 conversion happens. Both
impls should parse the same XML f64 text and get bit-equal f64,
yet 15,739 rows show C# `apex_rt` exactly ~1e-10 larger than
Rust. Source unknown — needs deeper drilling.

### New gate definition (user, 2026-05-20)

The stage1to4 1e-6 gate was relaxed too early. Stage 1-4 is only
truly "done" when the end-to-end run passes through Stage 7 +
blib WITHOUT any cross-tool sharing of intermediate files. The
proof that this bar is achievable is the existing parity in
Stage 5+ when fed Rust-frozen inputs. The new gate definition:

> "stage1to4 is only really done when it will allow stage5 to
> pass. We know stage5 passes with Rust stage1to4, but if it
> doesn't pass with C# stage1to4, then we need to keep working
> on C# stage1to4 until stage5 can pass with it."

This work stays on the current branch until end-to-end
`Compare-EndToEnd-Crossimpl.ps1` reaches PASS on Stellar (and
then Astral).


### Files uncommitted (ai repo)

- `ai/scripts/OspreySharp/Compare-EndToEnd-Crossimpl.ps1` — Pass-0
  end-to-end driver from yesterday (Stage 7 + blib comparison).
- `ai/scripts/OspreySharp/Compare-EndToEnd-Bisect-Crossimpl.ps1` —
  NEW Pass-1 driver written today, walks all natural boundaries.
- `ai/.tmp/json_tol_diff.py` — tolerance-based JSON diff (kept
  in `.tmp/` since it's a one-off diagnostic).
- `ai/.tmp/stage4_check.ps1` — Stage 4 `--no-join` verification
  (kept in `.tmp/` since it's a one-off diagnostic).

**Next session handoff**: For detailed startup protocol +
reproduce-and-debug-in-VS plan, read
`ai/.tmp/handoff-20260519_late_repro_in_VS.md` before starting work.


## 2026-05-20 mid-day — Stage 3 calibration deep bisection

### Test-Regression refactor: stop cross-tool freezing (committed ai/master `288b492`)

Reframed the regression test to match the new gate definition. Each
stage > stage1to4 now reads from `inputs-<side>/` (per-side input dir)
populated from THAT side's own previous-stage outputs.
`Get-StageInputDir` takes an optional `-Side` param; stage1to4 still
uses a shared `inputs/` for dataset files. Freeze-Stage1to4 +
Freeze-PostStage4 propagate each side's outputs to its own per-side
next-stage inputs.

Stellar Single result with the refactor:
- stage1to4 PASS at 1e-6 (unchanged)
- stage5 FAIL on all four dumps (standardizer SHA differs -6 bytes;
  subsample SAME SIZE / SHA differs (same row set, drifted feature
  values); svm_weights -7 bytes; percolator -66,558 bytes / 0.09%)

The new gate confirms what we suspected: with each side feeding its
own outputs forward, Stage 5 cannot pass at 1e-9 because Stage 4
features drift cross-impl.

### Stage 4 .scores.parquet per-column drift classification

Python-Pyarrow inspection of all 40 columns x 462,802 entries at
strict (bit-equal) and ULP-bucketed tolerance:

- Bit-equal across all rows: entry_id, charge, precursor_mz,
  bounds_snr, n_coeluting_fragments, consecutive_ions,
  ms1_precursor_coelution, ms1_isotope_cosine,
  median_polish_min_fragment_r2.
- Bit-equal modulo 1 catastrophic file-20 row 0 + a few ULP-class:
  apex_rt (99.9% + 1 catastrophic), start_rt, end_rt, peak_apex,
  fragment_coelution_sum/max, peak_area, peak_sharpness,
  mass_accuracy_*, median_polish_cosine/residual_ratio/correlation,
  sg_weighted_cosine, explained_intensity, bounds_area.
- The four drifters that feed Stage 5 SVM:
    - `xcorr`: only 6,193 bit-equal, 413,394 at <1e-7 (f32 cascade) -
      OFF LIMITS per user guidance.
    - `sg_weighted_xcorr`: only 32 bit-equal, 414,950 at <1e-7 - same.
    - `rt_deviation` / `abs_rt_deviation`: only 2,446 bit-equal,
      460,311 at <1e-9. NOT f32 cascade - comes from LOESS
      calibration model differing cross-impl.

### F10 vs F17 formatter mismatch (solved + committed)

The cal_match.txt "apex_rt 15,739 rows at exactly 1e-10 systematic
offset" mystery was 100% formatter-rounding artifact:
- Rust `{:.10}` uses round-half-to-even
- .NET Framework 4.7.2 `F10` uses round-half-away-from-zero
- On f64 values that land on a 10th-decimal rounding boundary, the
  two formatters disagree by exactly 1 in the last printed digit
- This created a fake "1e-10 systematic offset, always C# > Rust"
  signal even though the underlying f64s were bit-equal

Direct test at F17 (round-trip safe): all 186,118 matched cal_match
rows have bit-equal apex_rt cross-impl. Same for LDA discriminant /
q-value: max diff drops from 1e-10 (F10) to 5.06e-14 (F17), with most
values bit-equal modulo 1 ULP.

Commits:
- osprey `1089407` - cal_match dump :.10 -> :.17
- pwiz `43100b1917` - cal_match dump F10 -> F17
- osprey `3d2a0f5` - lda_scores dump :.10 -> :.17
- pwiz `af7088db35` - lda_scores dump F10 -> F17

Lesson: cross-impl diagnostic dumps need round-trip-safe precision
(16-17 fractional digits for f64). Earlier `:.10` choice was sound
intent ("avoid banker's vs half-up") but wrong implementation -
formatters still disagree at boundary cases regardless of precision.
The only fix is enough digits that the underlying f64 bits round-trip.
Pattern to watch for: systematic constant-direction constant-magnitude
diff at the format-precision boundary is the signature of this issue.

### Stage 3 calibration accumulator divergence (found via temporary OSPREY_DUMP_LOESS_GATE diagnostic - now reverted)

Added a one-shot bisection diagnostic that dumps every accumulated
calibration-match entry with (entry_id, is_decoy, q_value,
signal_to_noise, library_rt, measured_rt, passes-gate). Comparing
Rust vs C# dumps revealed the LOESS_INPUT 963-row delta is the tip
of an iceberg:

| Measure | Result |
|---|---|
| Rust `accumulated_matches` size | 192,289 entries |
| C# `matchArray` size | 186,118 entries |
| Rust-only entries (not in C#) | 6,240 (of which 6,118 are DECOYS, 122 targets) |
| C#-only entries (not in Rust) | 69 (all decoys) |
| Common entries | 186,049 |
| Common entries with bit-equal `q_value` | 76,414 (41%) |
| Common entries with bit-equal `snr` | 6,579 (3.5%) |
| Common entries flipping LOESS gate | 4,715 (1,403 q-only + 1,577 SNR-only + 1,735 both) |

SNR values differ wildly - e.g. entry 222 has Rust snr=15.94 vs C#
snr=2.06. This is NOT ULP drift; it is the two impls picking DIFFERENT
apex spectra during calibration matching, producing fundamentally
different SNR values from different peaks.

Important consolation finding: despite this Stage 3 calibration
chaos, Stage 4 main-search `apex_rt` in `.scores.parquet` is 99.9%
bit-equal cross-impl (462,375 of 462,802 rows; 426 at <=4 ULP; 1
catastrophic row). Stage 4 main-search and Stage 3 calibration use
INDEPENDENT candidate-spectrum-selection paths, so Stage 3 chaos
does NOT defeat Stage 4 directly. Stage 4 features drift on xcorr
(f32 cascade) and rt_deviation (LOESS-model cascade) but most other
features are bit-equal.

### What this means for the end-to-end gate

To pass Stage 5 percolator at 1e-9 with each side using its own
Stage 4 outputs, we need to reduce the .scores.parquet drift on
features that feed the SVM. The four real drifters are:
- xcorr, sg_weighted_xcorr - f32 cascade - OFF LIMITS without
  thorough vetting per user guidance
- rt_deviation, abs_rt_deviation - cascades from LOESS fit

To make rt_deviation bit-equal, the LOESS fit needs the same input
pairs. To get the same input pairs, calibration matching needs to
pick the same apex spectra. Currently 4,715 of ~186K common
entries pick different apex spectra -> fundamentally different LOESS
fits.

This is a deep Stage 3 calibration cross-impl bisection that
requires comparing the SCORING choices made by each impl during the
per-spectrum match loop. The temporary OSPREY_DUMP_LOESS_GATE
diagnostic gave the symptom; the root cause is upstream in the
calibration scoring code.

### Open questions for next session

1. What makes calibration matching pick different apex spectra
   cross-impl? Same library entry, same candidate spectra (we
   think), but different "best xcorr" picks. Need to dump per-entry
   per-candidate-spectrum xcorr scores during calibration to see
   where the scoring divergence enters.

2. Does the FINAL LOESS calibration model (the predict_rt function)
   actually produce similar predictions cross-impl despite the
   input-pair divergence? rt_deviation in .scores.parquet drifts
   at <1e-9 magnitude on 99.5% of rows. If the LOESS model is
   producing predictions that align at sub-1e-9, then Stage 4 main
   search doesn't suffer from the calibration chaos and the
   remaining problem is purely xcorr (off-limits).

3. Is the 6,118-decoy-entries-Rust-only an artifact of Rust running
   more calibration ATTEMPTS than C#? Need to count `attempts` /
   retry-with-widened-RT loop iterations on each side. If Rust has
   more attempts, that explains the larger accumulator.

### Commits landed today (cumulative)

| Repo | Commit | Content |
|------|--------|---------|
| osprey | `1fe4ff7` | iso_upper f64 mzML cvParam fix (yesterday) |
| osprey | `1089407` | cal_match :.10 -> :.17 |
| osprey | `3d2a0f5` | lda_scores :.10 -> :.17 |
| pwiz | `9982593f5b` | OspreySharp VERSION 26.6.0 -> 26.6.1 |
| pwiz | `43100b1917` | cal_match F10 -> F17 |
| pwiz | `af7088db35` | lda_scores F10 -> F17 |
| ai | `288b492` | Test-Regression per-side refactor + comparators + Snappy cleanup |

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260520_stage3_calibration_divergence.md`
before starting work.

### POSTSCRIPT (late afternoon) — the April fix was NEVER merged upstream

After user pointed at completed TODOs, history search shows commits
`c95b36c` and `dfda7cd` (the April f64 xcorr flip + restoration that
achieved 90.7% bit-equal cal_match cross-impl) live ONLY on the
`remotes/fork/fix/parquet-index-lookup` brendanx67 fork branch. They
are NOT in the current HEAD history (verified via
`git merge-base --is-ancestor c95b36c HEAD` returning false).

**Today's Stage 3 calibration divergence is NOT a regression — the
April fix was never adopted upstream.** Current
`fix/hpc-chain-stage7-second-pass-percolator` HEAD has been on the
original f32-primary code since 2026-02-05 (Mike MacCoss `d028d6e`).

Path forward for next session: cherry-pick or replay `dfda7cd`
(~120 lines: 108 in osprey-scoring/lib.rs + 14 in osprey/pipeline.rs)
to bring f64 xcorr primary path into the current branch. Per the
April TODO this should reproduce bit-equal cal_match cross-impl on
all 6 feature columns.

Second observation worth investigating: entry 222 cal_match SNR is
~2.06 on BOTH sides (before LDA), but after LDA training the Rust
`m.signal_to_noise` field is mutated in place to 15.94 (a z-score),
while C# stays at 2.06. The `passing_targets` filter then tests
`m.signal_to_noise >= 5.0` against a z-score on Rust vs raw SNR on
C#. This could be a separate fix from the f32→f64 flip (or could be
fixed by the April work — needs verification against the fork
branch).

### POSTSCRIPT 2 (late afternoon, continued) — naive April-fix replay does NOT work; needs coordinated cross-impl change

Attempted to replay the April dfda7cd f64-flip on the current osprey
branch. Done as additive `_f64` suffixed functions plus a rewrite of
`scorer.xcorr()` body to use f64 throughout (the calibration call site
in `run_coelution_calibration_scoring`).

The change DID exercise. Result was worse, not better:

| Boundary | Before f64 (current code) | After f64 (this experiment) |
|---|---|---|
| CAL_MATCH max_diff | 5.239e-10 | 3.876e-6 |
| LDA_SCORES max_diff | 5.063e-14 | 6.544e-5 |
| LDA sample diff | 1.110e-16 (1 ULP) | 1.889e-8 |
| LOESS_INPUT row count | 6,400 vs 7,363 | 6,400 vs 7,363 (unchanged) |

The user's morning warning was correct. The current C# code has been
tuned to "imitate Rust's f32 calculation" (i.e., C# is using f32-quirk
behavior intentionally to stay within ~1e-8 of Rust f32). Flipping
Rust to f64 unilaterally breaks the imitation alignment — Rust moves
to true f64 while C# stays on its imitation path, and they drift
~1e-6 apart (f32 ULP magnitude).

To actually re-establish bit-equal (April-style), the change must be
COORDINATED: flip Rust to f64 AND undo C#'s "imitate Rust f32" code
(returning C# to its natural f64 behavior). Both sides f64 ⇒ bit-
equal (like April). One side f64 + one side imitating f32 ⇒ worst-
case f32-magnitude divergence.

All experimental changes were reverted at end of session. osprey HEAD
back at `3d2a0f5`. No uncommitted state.

This finding strongly suggests the path forward is NOT a Rust-only
change. It needs the user to locate the C# "imitate Rust f32" code
(likely in `OspreySharp.Scoring.SpectralScorer` and helpers — could
be the `PreprocessSpectrumForXcorrInto` f32 path with conscious
imitation tweaks) and decide whether to coordinate a flip back to
natural f64 on both sides.

### POSTSCRIPT 3 (2026-05-20 evening) — C# calibration uses f32 cache via PerFileScoringTask.cs:2275; coordinated Rust+C# plan crystallized

User endorsed the f64-scratch-with-f32-storage architecture:
> Use f64 arrays for scratch (especially with recently implemented
> scratch pooling), and f32 for per-peptide storage arrays which
> impact total memory consumed.

Investigation in this evening session uncovered the precise mechanism
and committed the Rust half of the coordinated change.

**What's f32 vs f64 in the xcorr pipeline today (5 distinct points):**

| # | What | Type today | Pinned by | Free to flip? |
|---|---|---|---|---|
| 1 | Input intensities (Spectrum.intensities) | f32 | mzdata 0.63 quantization | NO |
| 2 | Binned sqrt-intensity accumulator | f32 | nothing | YES (scratch) |
| 3 | Sliding-window prefix sum (~100K bins) | f32 | nothing | YES (scratch) — dominant precision loss source |
| 4 | Cached preprocessed spectrum (HRAM ~100K) | f32 | per-spectrum-per-window memory budget | NO |
| 5 | Final dot-product accumulator | f32→f64 cast | nothing | YES (scalar) |

The user's strategy maps to: keep #1 + #4 as f32 (constrained), flip
#2 + #3 + #5 to f64 (free).

**C# is already architected for this dual-track design.** Read
`OspreySharp.Scoring.XcorrScratchPool`: `XcorrScratch` has BOTH
`double[] Binned/Windowed/Prefix/Preprocessed` AND `float[] BinnedF/
WindowedF/PrefixF`. SpectralScorer has both `ApplyWindowingNormalizationD`
(f64) and `ApplyWindowingNormalizationF` (f32) helpers. Two preprocess
variants: `PreprocessSpectrumForXcorr` returns `double[]` (f64 path),
`PreprocessSpectrumForXcorrF32` returns `float[]` (HRAM cache path).
The `xcorr_pool.rs` line-138 comment explicitly says "f32 matches Rust
upstream maccoss/osprey to halve cache memory vs f64."

**Which C# path Stage 3 calibration uses today** — read
`PerFileScoringTask.cs:2275-2276`:

```csharp
double xcorrApex = (windowPreprocessed != null && apexWindowIdx >= 0)
    ? s_calXcorrScorer.XcorrFromPreprocessed(windowPreprocessed[apexWindowIdx], entry)   // f32 cache path
    : s_calXcorrScorer.XcorrAtScan(apexSpectrum, entry);                                  // f64 path
```

The f32 cache path wins because `windowPreprocessed` is populated at
line 1550 by `PreprocessSpectrumForXcorrF32`. **So C# calibration's
xcorr_score field is computed via pure f32 throughout** —
PreprocessSpectrumForXcorrF32 (float[] binned, ApplyWindowingNormalizationF,
ApplySlidingWindowF) + XcorrFromPreprocessed(float[]). That's the
"imitate Rust f32" code path.

**Rust half (LANDED this session, commit `690194a`):** rewrote
`SpectralScorer::xcorr` body in `crates/osprey-scoring/src/lib.rs` to
inline f64 windowing + sliding-window subtraction, with `(intensity as
f64).sqrt()` widen-before-sqrt matching `Math.Sqrt((double)float)`.
Old `apply_windowing_normalization`/`apply_sliding_window` allocating
wrappers deleted (only `_into` f32 variants remain for the HRAM
per-window cache path). Build + fmt + clippy + tests all green.

**Verification on Stellar Single** (Compare-Stage1to4-Strict per-side):
Per-column cal_match max-diff against C#:

| Column | Before | After Rust patch | Status |
|---|---|---|---|
| apex_rt | 5.55e-16 noise | **0 bit-equal** | BIT-EQUAL ✓ |
| correlation | f64 noise | 4.97e-14 | f64 epsilon ✓ |
| libcosine | f64 noise | 5.55e-16 | f64 epsilon ✓ |
| **xcorr** | 5.24e-10 (f32-imitation alignment) | **3.876e-6** (f64 vs f32 cross-impl) | NEEDS C# CHANGE |
| snr | 5.24e-10 | 5.24e-10 unchanged | unrelated, separate root cause |

The xcorr column drift jumped from 5.24e-10 to 3.876e-6 because Rust
moved off the f32-imitation alignment and C# stayed on it. This is
EXPECTED and is the predicted outcome of a unilateral Rust flip. Not
a regression — the previous 5.24e-10 was f32-imitation parity, not
true f64 parity.

**C# half (NEEDS USER DECISION):** Switch C# calibration to use the
f64 path. Three options ranked by trade-off:

1. **One-line switch (simplest, has perf cost).** Change
   `PerFileScoringTask.cs:2275-2276` to unconditionally use
   `XcorrAtScan(apexSpectrum, entry)`. Uses already-existing C# f64
   code path. Perf cost: one redundant f64 preprocess per calibration
   apex match (~186K matches × ~100K bins on Stellar Single = ~18.6B
   extra ops, estimated 10-30s additional calibration wall). Memory
   cost: zero (uses existing pooled scratch).

2. **F64 calibration cache (faster, more memory).** Build a parallel
   `double[][]` cache in `PerFileScoringTask.cs:1550` (calibration
   only — not main search). Then `XcorrFromPreprocessed(double[], entry)`
   (already exists in SpectralScorer.cs:171) bit-equally matches
   Rust's f64 path with no redundant preprocess. Memory cost:
   ~800 MB transient per window during calibration instead of 400 MB
   (calibration-only, frees after).

3. **F64-internal + f32-storage cache (most invasive, perf-neutral).**
   Add a new `PreprocessSpectrumForXcorrF32_F64Internal` that does f64
   preprocessing internally and narrows to f32 at the final cache
   write. Then `XcorrFromPreprocessed(float[])` reads the
   f64-noise-floor f32 cache and bit-equals Rust if Rust does the same.
   Requires identical Rust path: flip XcorrScratch to f64 internally
   and adapt `preprocess_spectrum_for_xcorr_into` to do f64-internal +
   f32-cast at output. Memory cost: same as today on both sides
   (cache stays f32). Implementation cost: ~150 lines split across
   Rust + C#.

Recommendation: Option 1 first to validate cross-impl bit-equal
calibration parity end-to-end (commit cycle, measure perf impact).
Then if perf cost is too high, lift to Option 2 (cheap upgrade).
Option 3 is only needed if both 1 and 2 prove inadequate (unlikely).

**File pointers for next session:**
- C#: `pwiz_tools/OspreySharp/OspreySharp/Tasks/PerFileScoringTask.cs:2275`
- C# scratch pool: `pwiz_tools/OspreySharp/OspreySharp.Scoring/XcorrScratchPool.cs`
- C# scorer with both paths: `pwiz_tools/OspreySharp/OspreySharp.Scoring/SpectralScorer.cs:92,125,171,226,280,303,508`
- Rust scorer.xcorr() (this session's commit): `crates/osprey-scoring/src/lib.rs:2076-2178`

**Open question still on the docket:** The xcorr-column ULP drift is
the headline issue. The SNR column 5.24e-10 drift remains UNCHANGED
across the entire session and is a separate root cause (likely the
LDA in-place mutation of `m.signal_to_noise` to a z-score on the Rust
side only — entry 222 evidence). Resolve xcorr parity first; revisit
SNR after.

**Commits landed today (cumulative):**

| Repo | Commit | Content |
|------|--------|---------|
| osprey | `1fe4ff7` | iso_upper f64 mzML cvParam fix (yesterday) |
| osprey | `1089407` | cal_match :.10 -> :.17 |
| osprey | `3d2a0f5` | lda_scores :.10 -> :.17 |
| osprey | `690194a` | scorer.xcorr f64 inline (this session) |
| pwiz | `9982593f5b` | OspreySharp VERSION 26.6.0 -> 26.6.1 |
| pwiz | `43100b1917` | cal_match F10 -> F17 |
| pwiz | `af7088db35` | lda_scores F10 -> F17 |
| ai | `288b492` | Test-Regression per-side refactor + comparators + Snappy cleanup |
| ai | `8ff9fa5` | TODO mid-day update |
| ai | `450b35d` | handoff pointer |
| ai | `61e0105` | April-fix-not-merged note |
| ai | `e17a891` | f64 replay failed note |

### POSTSCRIPT 4 (2026-05-20 mid-afternoon) — Option 3 landed; calibration aligned, Stage 4 xcorr at f32 single-cast floor

User picked Option 3 (f64-internal / f32-storage cache) over Option 1
(one-line C# switch with perf cost on Astral) and Option 2 (parallel
double[][] calibration cache, +400 MB transient). Option 3 keeps the
cache memory budget at today's 400 KB per spectrum but moves the
windowing / sliding-window cascade math to f64, so cache values now
carry single-cast precision rather than f32-cascade noise. Memory
overhead is negligible (~19 MB total scratch growth at 16 threads).

**Rust changes** (`osprey a44f752`):
- `xcorr_pool.rs`: XcorrScratch.binned/windowed/prefix flipped from
  `Vec<f32>` to `Vec<f64>`. Per-thread scratch ~1.2 MB → ~2.4 MB on
  HRAM; per-spectrum cache (`Vec<Vec<f32>>`) unchanged.
- `lib.rs::apply_windowing_normalization_into`: f64 in, f64 out;
  mirrors C# `ApplyWindowingNormalizationD` bit-for-bit.
- `lib.rs::apply_sliding_window_into`: f64 spectrum + f64 prefix
  scratch in, f32 result out. Single deterministic f64→f32 cast at
  final store.
- `lib.rs::preprocess_spectrum_for_xcorr_into`: bin with
  `(intensity as f64).sqrt()` widen-before-sqrt. Output signature
  unchanged (`&mut [f32]`); HRAM callers in pipeline.rs need no
  updates.

**C# changes** (`pwiz 6c17c20717`):
- `SpectralScorer.PreprocessSpectrumForXcorrF32IntoBuffers`: takes
  `double[] binned/windowed/prefix` + `float[] preprocessed`. Bin step
  uses `Math.Sqrt(float)` (implicit widen-before-sqrt) so it bit-equals
  Rust's `(intensity as f64).sqrt()`.
- New `ApplySlidingWindowDIntoF32` helper: f64 inputs, f32 result with
  final cast.
- `PreprocessSpectrumForXcorrInto`: switched from `BinnedF/WindowedF/
  PrefixF` (float[]) to `Binned/Windowed/Prefix` (double[]). Same
  XcorrScratch pool, no new allocation.
- Removed obsolete `XcorrScratch.BinnedF/WindowedF/PrefixF` fields
  and `ApplyWindowingNormalizationF` / `ApplySlidingWindowF` helpers.

**Verification on Stellar Single** (Compare-Stage1to4-Strict + per-column
analysis joined by `entry_id+charge+scan_number`):

| Boundary | Column | max diff | Status |
|---|---|---|---|
| cal_match | apex_rt | 0 | bit-equal ✓ |
| cal_match | correlation | 4.97e-14 | f64 epsilon ✓ |
| cal_match | libcosine | 5.55e-16 | f64 epsilon ✓ |
| cal_match | xcorr | **4.43e-8** | down from 3.876e-6 (~100x) |
| cal_match | snr | 5.24e-10 | unchanged (separate root cause) |
| .scores.parquet | peak_apex | **0** | 100% bit-equal ✓ |
| .scores.parquet | apex_rt | 3.55e-15 | 462,375 bit-equal + f64 epsilon ✓ |
| .scores.parquet | rt_deviation | **2.32e-11** | LOESS cascade now tight |
| .scores.parquet | peak_area | 4.42e-9 | overwhelmingly bit-equal ✓ |
| .scores.parquet | xcorr | **5.41e-7** | at f32 single-cast floor (was f32 cascade) |
| .scores.parquet | sg_weighted_xcorr | 3.52e-7 | same |

**What the residual ~1e-7 floor represents.** The cache stores f32
values that get cast once from f64. C# `XcorrFromPreprocessed(float[],
entry)` sparse-sums them into a `double xcorrRaw` accumulator (implicit
f32→f64 promote on read). Rust `xcorr_sparse` sums into an `f32`
accumulator and casts to f64 only at the final scale. The two
accumulator orders / types produce slightly different results even on
bit-equal f32 caches — that's the residual. Aligning Rust to f64-sum
in xcorr_sparse would close this; deferred as a follow-up.

**Open items still on the docket:**
- `snr` 5.24e-10 unchanged. Still the LDA in-place mutation of
  `m.signal_to_noise` to a z-score on the Rust side only (entry 222
  evidence). Worth a focused look once xcorr parity is locked in.
- `LOESS_INPUT` row count still differs (6,400 vs 7,363). Now that
  xcorr cascade is aligned, the residual is almost certainly the SNR
  gate (depends on the LDA-mutated SNR).
- Rust `xcorr_sparse` sums in f32 vs C# `XcorrFromPreprocessed`
  sums in f64. Aligning these would push Stage 4 xcorr from
  ~5e-7 (single-cast floor) toward bit-equal. Deferred.

### Commits landed today (cumulative)

| Repo | Commit | Content |
|------|--------|---------|
| osprey | `1089407` | cal_match :.10 -> :.17 |
| osprey | `3d2a0f5` | lda_scores :.10 -> :.17 |
| osprey | `690194a` | scorer.xcorr f64 inline (surgical patch) |
| osprey | `a44f752` | XcorrScratch + cache build flipped to f64-internal/f32-storage |
| pwiz | `9982593f5b` | OspreySharp VERSION 26.6.0 -> 26.6.1 |
| pwiz | `43100b1917` | cal_match F10 -> F17 |
| pwiz | `af7088db35` | lda_scores F10 -> F17 |
| pwiz | `6c17c20717` | HRAM XCorr preprocess: f64-internal / f32-storage cache |
| ai | `288b492` | Test-Regression per-side refactor + comparators |
| ai | `8ff9fa5` | TODO mid-day |
| ai | `450b35d` | handoff pointer |
| ai | `61e0105` | April-fix-not-merged |
| ai | `e17a891` | f64 replay failed |
| ai | `5c7a30f` | TODO postscript 3 (3-option breakdown) |
| ai | `3129f5d` | TODO split into phase1 + phase2 |

### POSTSCRIPT 5 (2026-05-20 mid-afternoon) — chasing the three residual differences

User picked "keep chasing." Pulled three open items:
1. Rust `xcorr_sparse` f32 accumulator → C# f64 accumulator
2. `snr` 5.24e-10 (purported LDA in-place mutation)
3. `LOESS_INPUT` row count delta (6,400 vs 7,363)

Plus discovered + fixed three additional bugs along the way.

**Win 1 — Rust xcorr accumulator alignment** (`osprey f41ff88`):
- Flipped `xcorr_sparse` to widen each f32 cache value to f64 on read
  and accumulate in f64 (matches C# `XcorrFromPreprocessed(float[])`
  which does `double xcorrRaw += preprocessed[bin]` implicitly).
- Replaced `scorer.xcorr()` inline body with delegation to
  `xcorr_at_scan` so both paths go through the same f32-cache-narrowing
  pattern C# uses.
- Result: cal_match xcorr 4.43e-8 → **5.11e-15** (f64 epsilon). Stage 4
  .scores.parquet xcorr **100% bit-equal** cross-impl. sg_weighted_xcorr
  **100% bit-equal**. peak_apex 100% bit-equal. apex_rt 462,375/462,802
  bit-equal. LDA scores cascade: 3.29e-5 → 4.95e-14 (f64 epsilon).

**Win 2 — Disproved LDA SNR mutation; found real LOESS_INPUT bug**
(`osprey b80d86b`):
- The morning's hypothesis (Rust LDA mutating `m.signal_to_noise`
  in-place to z-score) was wrong. No mutation site exists in
  `calibration_ml.rs`. The 5.24e-10 cal_match.snr drift is f64-epsilon
  noise (single ULP at value ~3e5). Threshold analysis showed **zero
  snr-gate flips** at the 5.0 threshold cross-impl. Entry 222 cal_match
  SNR is 2.06 on BOTH sides.
- Real root cause of LOESS_INPUT row delta: Rust's `dump_loess_input`
  was called at pipeline.rs:1000 BEFORE the pass-2 refinement at line
  1024, so the dump captured pass 1's 6,398 input rows even when pass
  2's 7,361 were what the LOESS fit actually used. C# overwrites the
  dump unconditionally on pass 2.
- Also fixed `num_confident_peptides` metadata stuck on pass 1's count
  when pass 2 was accepted.
- Result: **LOESS_INPUT now PASS bit-equal** cross-impl.

**Win 3 — C# CalibrationMetadata populated** (`pwiz e64bb5abcc`):
- C# was writing `NumConfidentPeptides = 0` and `NumSampledPrecursors = 0`
  hard-coded at `PerFileScoringTask.cs:1051-1052`. Now plumbed through
  via new `CalibrationPassResult.MatchCount` field + `out int
  numSampledPrecursors` on `RunCalibration`. Populated with
  `rtCalibration.Stats().NPoints` and pass 1's matchArray.Length to
  match Rust's `num_confident_peptides` and `num_sampled_precursors`
  semantics.
- Result: max cal_json diff dropped from 1.92e+5 (at
  num_sampled_precursors) → 1.75e+2 (at next-largest remaining).

**Win 4 — MS1 envelope tolerance unit fix** (`osprey 99c9e30`):
- Rust was passing `config.precursor_tolerance.tolerance` directly as
  `tolerance_ppm` to `IsotopeEnvelope::extract`, regardless of the
  configured unit. For Stellar (unit-resolution: `tolerance=1.0,
  unit=Mz`), this treated 1.0 Da as 1.0 ppm and produced an absurdly
  tight ~0.5 mDa window. `envelope.has_m0()` failed on ~99.8% of
  matches; only 18 of 7,361 entries contributed to ms1_calibration
  (vs C# 193, 10x undercount).
- Added `ms1_envelope_tolerance_ppm` helper matching C# behavior:
  `unit == Ppm ? tolerance : 10.0`.
- Found via `OSPREY_DIAG_MS1` instrumentation: `tol_ppm=1.0
  peaks_in_m0_window=0 has_m0=false` on all sampled entries.
- Result: **ms1_calibration drift eliminated** from cal_json
  divergence list (was max 1.75e+2 at ms1_calibration.count).

**Win 5 — LOESS sort tiebreak** (`osprey adfbea4`, `pwiz edb159ae23`):
- Sort pairs by `(library_rt, measured_rt)` instead of just
  `library_rt`, so duplicate-x positions are deterministic
  cross-impl regardless of input order.
- Result: marginal — eliminates cosmetic input-order dependency,
  but the underlying LOESS prediction divergence at duplicate-x
  remains (see "deferred" below).

**Stellar Single boundary status after this round:**

| Boundary | Status | Max diff |
|---|---|---|
| CAL_SAMPLE rust_cal_sample.txt | PASS | bit-equal |
| CAL_SAMPLE rust_cal_scalars.txt | FAIL | 5.12e-13 (f64 epsilon) |
| CAL_SAMPLE rust_cal_grid.txt | PASS | bit-equal |
| CAL_WINDOWS | PASS | bit-equal |
| CAL_MATCH | FAIL | 5.24e-10 (snr ULP floor) |
| LDA_SCORES | FAIL | 4.95e-14 (f64 epsilon) |
| **LOESS_INPUT** | **PASS** ✓ | bit-equal (was FAIL) |
| CAL_JSON | FAIL | 7.04e-1 (LOESS dup-x swap; ms1 drift gone) |
| SCORES_PQ Stage 4 | FAIL | xcorr/sg_xcorr/peak_apex **bit-equal**; rt_deviation 2.32e-11 |

Boundary count unchanged at 4 PASS / 5 FAIL but the FAIL contents
have tightened dramatically — nearly all remaining drift is at f64
epsilon or single ULP. The CAL_JSON FAIL is now dominated by one
LOESS dup-x prediction divergence.

**Deferred — LOESS prediction divergence at duplicate-x points
(task #82):** Both impls feed bit-equal LOESS inputs (verified row-
by-row sed comparison shows identical (lib_rt, measured_rt) at every
index). After (x, y) sort tiebreak, abs_residuals[5] and abs_residuals[6]
are still swapped cross-impl with prediction divergence ~9 mDa at
x=1.93. Suspected root cause: `find_k_nearest_sorted` uses INDEX-based
k-NN, so i=5 and i=6 (both at x=1.93) get different neighborhood
windows. Numerical reduction differences between Rust ndarray weighted
least squares and C# manual implementation could amplify f64-epsilon
prediction noise through bisquare weighting. Needs dedicated focused
investigation.

### Commits landed this round

| Repo | Commit | Content |
|------|--------|---------|
| osprey | `f41ff88` | XCorr alignment: f64 accumulator + scorer.xcorr via cache narrowing |
| osprey | `b80d86b` | Calibration pass 2: refresh LOESS dump + num_confident_peptides metadata |
| osprey | `99c9e30` | Treat non-ppm precursor tolerance as 10 ppm default for MS1 envelope |
| osprey | `adfbea4` | LOESS: sort by (lib_rt, measured_rt) tuple for deterministic dup-x order |
| pwiz | `e64bb5abcc` | Populated CalibrationMetadata NumConfidentPeptides + NumSampledPrecursors |
| pwiz | `edb159ae23` | LOESS: ThenBy on y for deterministic sort at duplicate library RT |

### POSTSCRIPT 6 (2026-05-20 late afternoon) — LOESS outer/inner sort mismatch fixed; cal_json at f64 epsilon

After committing the (x, y) tiebreak fix in both LOESS implementations
(adfbea4, edb159ae23), the cal_json abs_residuals[5]/[6] swap PERSISTED.
Investigation via `model_params.fitted_rts` revealed: predictions were
bit-equal cross-impl (both 2.098903079075325), but the RESIDUALS were
swapped. Tracing back showed C# has a DOUBLE-SORT BUG.

**Root cause** (`pwiz 3ec9236dca`):
- `RTCalibration.cs:120` outer wrapper sorts by `libraryRts` ONLY.
- `LoessRegression.cs:258` inner sort uses `(x, y)` tuple (the
  postscript-5 fix).
- At duplicate-x positions, the two sorts produce different orders.
  Outer `y[i]` and inner `fitted[i]` end up corresponding to
  DIFFERENT data points, so `residuals[i] = y[i] - fitted[i]` is
  mismatched on the duplicate-x rows.
- Rust is consistent because `rt.rs::fit` does a SINGLE sort by
  `(x, y)` tuple at line 123 — y[i] and fitted[i] always correspond.
- Fix: outer C# sort gains `ThenBy(i => measuredRts[i])` to match
  the inner sort.

**Cross-impl effect on Stellar Single calibration.json:**
- max_diff: 7.04e-1 → **4.71e-12** (~11 orders of magnitude tighter)
- All `rt_calibration.model_params.abs_residuals[i]` now at f64
  epsilon cross-impl
- `rt_calibration.mad`: 8.14e-13 (f64 noise)
- The remaining cal_json drift is f64 cascade noise in the bisquare-
  weighted refit — essentially bit-equal

**Final Stellar Single boundary status:**

| Boundary | Status | Max diff |
|---|---|---|
| CAL_SAMPLE rust_cal_sample.txt | PASS | bit-equal |
| CAL_SAMPLE rust_cal_scalars.txt | FAIL | 5.12e-13 (f64 noise; mz_min 1-ULP differs) |
| CAL_SAMPLE rust_cal_grid.txt | PASS | bit-equal |
| CAL_WINDOWS | PASS | bit-equal |
| CAL_MATCH | FAIL | 5.24e-10 (snr ULP floor at value ~3e5; intensity precision) |
| LDA_SCORES | FAIL | 4.95e-14 (f64 epsilon) |
| LOESS_INPUT | PASS | bit-equal |
| CAL_JSON | FAIL | **4.71e-12** (was 7.04e-1; f64 epsilon now) |
| SCORES_PQ Stage 4 | FAIL | xcorr/sg_xcorr/peak_apex bit-equal; rt_deviation 2.13e-11 |

All FAILs are at f64 epsilon, single ULP precision, or upstream
intensity precision. The cross-impl parity work has effectively
reached the architectural floor on Stellar Single.

**Commits this round (cumulative for the day, 14 across 3 repos):**

| Repo | Commit | Content |
|------|--------|---------|
| pwiz | `3ec9236dca` | Fixed outer/inner sort mismatch at duplicate library RT |

### POSTSCRIPT 7 (2026-05-20 evening) — F17 → G17 print format + IEEE-correct parsers; CAL_SAMPLE passes, CAL_MATCH at f64 epsilon

After the LOESS bit-equal fixes (postscript 6), the next-largest
cross-impl drift was CAL_MATCH snr at 5.24e-10. Initial debugging
attributed this to f32 cascade in XIC intensity reading. Wrong.

**Real root cause**: .NET Framework 4.7.2's `F17` format truncates
double output at ~15 significant digits and pads with zeros. The
"5.24e-10 snr drift" was the comparator parsing those truncated
strings back to f64 values that differed by 9 ULP from the original.
Underlying f64 values were essentially bit-equal cross-impl.

**Fix** (`pwiz 11943b19dd`, `pwiz 1b60a781ab`):
- Switch cal_scalars, cal_match, lda_scores dumps from F17 → G17
  for the f64 fields. G17 prints 17 significant digits required for
  round-trip-safe representation. F17 in .NET Framework 4.7.2 caps
  at ~15 sig figs.
- DiannTsvLoader (`ParseDouble`, `ParseFloat`, `ParseDoubleOrDefault`)
  switch to `XmlConvert.ToDouble`/`ToSingle` for IEEE-754 correct
  parsing of TSV library values.
- MzmlReader (`pwiz 7b057b1f7d`) similarly switches all 13
  `double.TryParse` cvParam callsites to `TryParseXmlDouble`. Note
  .NET Framework 4.7.2's XmlConvert.ToDouble apparently has the
  same parser limitation as double.TryParse on the specific
  cvParam values producing the apex_rt 137-row 2-ULP drift —
  the fix is still correct in principle and helps on .NET 5+ /
  values that fall in the correctable parser range.

**Per-column cal_match drift after this round**:

| Column | Before postscript 7 | After G17 |
|---|---|---|
| apex_rt | bit-equal (artifact) | 3.55e-15 on 137/186118 rows (parser ULP floor) |
| correlation | 4.97e-14 (f64 epsilon) | **bit-equal** |
| libcosine | 5.55e-16 (f64 epsilon) | **bit-equal** |
| xcorr | 5.11e-15 (f64 epsilon) | **6.94e-18 (sub-epsilon)** |
| snr | 5.24e-10 (thought f32 cascade) | **6.94e-18 (sub-epsilon)** |

cal_match boundary max_diff: 5.24e-10 → **3.55e-15** (5 orders tighter).

**Final boundary status this session (Stellar Single)**:

| Boundary | Status | Max diff |
|---|---|---|
| CAL_SAMPLE rust_cal_sample.txt | PASS | bit-equal |
| CAL_SAMPLE rust_cal_scalars.txt | **PASS** (was FAIL) | bit-equal |
| CAL_SAMPLE rust_cal_grid.txt | PASS | bit-equal |
| CAL_WINDOWS | PASS | bit-equal |
| CAL_MATCH | FAIL | 3.55e-15 (apex_rt 137 rows at .NET parser ULP floor) |
| LDA_SCORES | FAIL | 4.84e-14 (f64 epsilon cascade) |
| LOESS_INPUT | PASS | bit-equal |
| CAL_JSON | FAIL | 4.71e-12 (LOESS bisquare f64 cascade) |
| SCORES_PQ Stage 4 | FAIL | xcorr/sg_xcorr/peak_apex bit-equal; rt_deviation 2.13e-11 |

**Boundary count**: 5 PASS / 4 FAIL (was 4 PASS / 5 FAIL at session
start). All remaining FAILs at single-ULP f64 noise or .NET parser
precision floor.

**Commits this round (cumulative for the day, 17 across 3 repos)**:

| Repo | Commit | Content |
|------|--------|---------|
| pwiz | `11943b19dd` | DiannTsvLoader IEEE-correct + cal_scalars G17 |
| pwiz | `1b60a781ab` | cal_match + lda_scores dumps F17 → G17 |
| pwiz | `7b057b1f7d` | MzmlReader cvParams use XmlConvert.ToDouble |

**Deferred / known limitations**:

1. **CAL_MATCH apex_rt 137-row 2-ULP drift** (.NET Framework 4.7.2
   parser limitation on specific cvParam values like "17.0286203070330").
   Both `double.TryParse` and `XmlConvert.ToDouble` have the same
   limitation. Would be fixed by .NET 5+ migration or a custom
   IEEE-correct parser (e.g. David Gay-style).

2. **CAL_JSON 4.71e-12** — LOESS bisquare-weighted refit f64
   cascade. Eliminating would require identical floating-point
   operation order in both LOESS implementations.

3. **LDA_SCORES 4.84e-14** — f64 cascade through LDA classifier
   weights / mean accumulation. Same operation-order limitation.

4. **SCORES_PQ Stage 4 rt_deviation 2.13e-11** — cascade from LOESS
   predictions. Improves automatically if (2) is addressed.

The cross-impl parity work has effectively reached the architectural
floor for cross-impl numerical equality on .NET Framework 4.7.2 +
Rust f64. Further reduction would require either the .NET 5+
migration or coordinated rewrite of LOESS / LDA internals to align
floating-point reduction order.

### POSTSCRIPT 8 (2026-05-20 evening, continued) — .NET 8.0 build gets us essentially bit-equal

Tested the same build path against the .NET 8.0 OspreySharp binary
(`bin\x64\Release\net8.0\OspreySharp.exe`) instead of the canonical
net472. .NET 5+ ships with the Eisel-Lemire IEEE-754-correct double
parser, so the .NET Framework 4.7.2 parser ULP limitations should
vanish. Result far exceeded expectations.

**Stellar Single boundary status on .NET 8.0** (vs net472 in parens):

| Boundary | net8.0 max | net472 max |
|---|---|---|
| CAL_SAMPLE rust_cal_scalars.txt | bit-equal | bit-equal |
| CAL_MATCH | **6.94e-18** (sub-epsilon) | 3.55e-15 |
| LDA_SCORES | 4.84e-14 (real f64 cascade) | 4.84e-14 |
| CAL_JSON | **4.44e-16** (n_above_1e-15=0) | 4.71e-12 |
| SCORES_PQ Stage 4 | only sg_weighted_cosine + median_polish_residual_correlation at 1 ULP; **everything else bit-equal** | rt_deviation 2.13e-11, peak_sharpness 1.17e-6, etc. |

**Per-column Stage 4 .scores.parquet on .NET 8.0:**

| Column | Status |
|---|---|
| entry_id, charge, precursor_mz, etc. | bit-equal (always were) |
| **apex_rt, start_rt, end_rt** | **bit-equal** (was 3.55e-15 + 427 rows) |
| **bounds_area, peak_area, peak_apex** | **bit-equal** (was 4.42e-9 "f32 cascade") |
| **peak_sharpness** | **bit-equal** (was 1.17e-6 "f32 cascade") |
| **xcorr, sg_weighted_xcorr** | **bit-equal** (same as net472) |
| **rt_deviation, abs_rt_deviation** | **bit-equal** (was 2.13e-11 "LOESS f64 cascade") |
| explained_intensity, median_polish_*, mass_accuracy_* | **bit-equal** (was 1.87e-14 / 1.17e-6) |
| sg_weighted_cosine | 1-2 ULP diffs (267,532 rows) |
| median_polish_residual_correlation | 1-2 ULP diffs (288,665 rows) |

**Massive realization: nearly every "f32 cascade" and "LOESS f64
cascade" we attributed to internal arithmetic was actually driven by
.NET Framework 4.7.2's 1-2 ULP parser bug.** Two distinct propagation
chains:

1. **Parser → apex_rt → peak boundary indices → all peak shape
   features.** If C# parses mzML cvParam "17.0286203070330" to a
   different f64 than Rust, apex_rt differs by 2 ULP, peak boundary
   index selection differs, peak_sharpness / peak_area / bounds_area
   compute over slightly different ranges → "f32 magnitude" drift.

2. **Parser → cvParam mz/intensity values → cascading.** Smaller
   contribution but compounds with #1.

On .NET 8.0 with the Eisel-Lemire parser, both chains collapse: the
parsed f64 values are IEEE-correct, downstream peak selection is
deterministic, and almost all "cascades" become bit-equal.

**Stage 4 .scores.parquet went from 8 columns with significant drift
to just 2 columns with 1-2 ULP f64 noise.** That's the real
architectural floor — only the genuine f64 reduction-order
limitations remain (weighted cosine sum, median polish correlation
sum).

**Implications for the work plan:**

- .NET 8.0 is the right target for cross-impl bit-equality.
  net472 hits the parser precision floor; net8 doesn't.
- The two remaining f64-cascade columns (sg_weighted_cosine and
  median_polish_residual_correlation) could potentially be aligned
  with focused sum-order matching, but this would be a coordinated
  Rust + C# change.
- The XmlConvert.ToDouble work we did (`7b057b1f7d`) is still
  valuable: it makes net472 incrementally better in the cases where
  XmlConvert is more correct than double.TryParse, and is required
  by code that runs on both targets to behave consistently.

**Verification commands** (Stellar Single):
```
# net472 (canonical Skyline binary):
pwsh -File ./ai/scripts/OspreySharp/Compare-Stage1to4-Strict.ps1 -Dataset Stellar -Files Single -Force

# net8.0 (eliminates parser-driven cascades):
# Temporarily edit Compare-Stage1to4-Strict.ps1 line 85 to point at
# bin\x64\Release\net8.0\OspreySharp.exe, then re-run -Force.
```

The `-Framework net472|net8.0` switch was added to
Compare-Stage1to4-Strict.ps1 in ai `0e00286` so toggling the build
target is now a single CLI arg, no script edit needed.

### Commits this round (cumulative)

| Repo | Commit | Content |
|------|--------|---------|
| pwiz | `11943b19dd` | DiannTsvLoader IEEE-correct + cal_scalars G17 |
| pwiz | `1b60a781ab` | cal_match + lda_scores dumps F17 → G17 |
| pwiz | `7b057b1f7d` | MzmlReader cvParams use XmlConvert.ToDouble |
| ai | `f231ea1` | TODO postscript 7 |
| ai | `9cdd891` | TODO postscript 8 (.NET 8.0 is the proof) |
| ai | `0e00286` | Compare-Stage1to4-Strict -Framework switch |
| ai | `32f951e` | TODO Current Status reframed with .NET 8.0 as proof |

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260516_ospreysharp_wsl_parity.md` before starting
work. Cross-impl Stage 1-4 parity sprint is COMPLETE; the next
natural target if the sprint resumes would be either (a) coordinated
sum-order alignment for the 2 remaining f64-cascade columns on
net8.0 (sg_weighted_cosine + median_polish_residual_correlation),
or (b) pivoting to Stage 5+ percolator parity which this sprint
deliberately did not address.

## Postscript 9 — Option A overnight: Stages 1-6 per-side bit-equal on net8.0 (2026-05-20 night)

User asked for an overnight push on Option A: eliminate the touch
point where C# must rely on Rust output to stay passing on downstream
stages. Goal: pass all per-side stages with no information sharing.

### Outcome

**Stages 1-4, 5, and 6 now PASS per-side bit-equal on net8.0.**
Stage 7 still fails due to a separate harness-level asymmetry
(see below). Two `.scores.parquet` columns that previously drifted
at 1-2 ULP cross-impl are now bit-equal, and the per-side Stage 5
standardizer / SVM / percolator cascade is closed.

### What landed

| Repo | Commit | Branch | Content |
|------|--------|--------|---------|
| osprey | `8dc0441` | fix/hpc-chain-stage7-second-pass-percolator | compute_cosine_at_scan single-pass form + write_scores_parquet_with_metadata sorts by (entry_id, charge, scan_number) before writing |
| pwiz | `9a72565527` | Skyline/work/20260516_ospreysharp_wsl_parity | TukeyMedianPolish.PearsonCorrelationRaw moment form + both WriteScoresParquet overloads sort by (EntryId, Charge, ScanNumber) before writing |
| ai | `42b60a7` | master | Test-Regression-Hybrid.ps1 (shared Stage 4 → per-side from Stage 5) + Test-Regression-RustFeed.ps1 (Rust feeds both at every boundary) for cross-impl pipeline-shape investigation |

All three pushed.

### Root causes addressed

**Stage 4 column-level cross-impl drift** (the two columns the
sprint-complete summary flagged as 1-2 ULP):

* `sg_weighted_cosine` drifted because Rust's `compute_cosine_at_scan`
  did per-element divide before sum (`Σ (a/norm_a) * (b/norm_b)`)
  while C# used the more common single-pass form
  (`Σ a*b` then divide once at end). Mathematically equivalent;
  bit-different in f64. Aligned Rust to the C# / `cosine_angle`
  pattern, which is also what other Rust cosine helpers use.

* `median_polish_residual_correlation` drifted because C#'s
  `TukeyMedianPolish.PearsonCorrelationRaw` used the two-pass
  centered Pearson form while Rust used the single-pass moment form.
  C# already has a separate `PearsonCorrelation.Pearson` helper in
  the moment form (used by all the other Pearson features which were
  already bit-equal cross-impl) — switched the local helper to the
  same form. Both columns now show 0 rows differ across all 462K
  rows on Stellar Single net8.0.

**Stage 5 standardizer cascade** (the per-side Stage 5 had every
PSM's percolator score differing by up to 41, with q-values flipping
across [0,1] for ~half of PSMs):

* Root cause: per-side parquets had completely different physical
  row orders even though their logical column data was bit-equal.
  Rust wrote entries in `entry_id` ascending (0, 1, 3, 4, 5...);
  C# wrote in target-decoy-paired order (38 (T), 38's decoy, 79 (T),
  79's decoy...). The strict comparator aligns rows by key before
  diffing, so it correctly reported "0 rows differ" — but Stage 5's
  standardizer reduces 300K bit-equal samples in physical row order,
  so the running sum hit different addition orders on each side,
  producing ~1e-15 to 1e-10 drift per feature mean / stddev. SVM
  then amplified that into 50-70% weight drift and 41-point score
  differences. Fixed by adding canonical sort
  (entry_id, charge, scan_number) to both parquet writers right
  before the column fill. Zero algorithmic impact — only enforces
  deterministic physical row order. With the sort, per-side Stage 5
  dumps are now byte-identical and Stage 6 dumps follow.

### Why net8.0 only

These fixes target net8.0 (the build target the sprint pivoted to
in postscript 8). On net472 the Stage 4 .NET Framework parser still
adds its own 1-2 ULP per double parsed from XML, which cascades the
same way through ungated parts of the pipeline. The net8.0 result is
the clean architectural floor; net472 carries the parser-driven noise
that won't be fixed without leaving .NET Framework 4.7.2.

### Verification

```
# Confirms Stage 4 sg_weighted_cosine + median_polish_residual_correlation
# are bit-equal (the parquet log shows "0 rows differ" for both):
pwsh -File ./ai/scripts/OspreySharp/Compare-Stage1to4-Strict.ps1 \
    -Dataset Stellar -Files Single -Force -Framework net8.0

# Confirms Stages 1-4, 5, 6 PASS per-side end-to-end (each side runs
# its own pipeline with no Rust output sharing; Stage 7 still FAILs):
pwsh -File ./ai/scripts/OspreySharp/Test-Regression.ps1 \
    -Dataset Stellar -Files Single -StopAfterStage blib -Continue -Force
```

Per-side stage results on net8.0 (Stellar Single):

| Stage | Result | Notes |
|---|---|---|
| stage1to4 | PASS | Test-Regression 1e-9 gate (strict-strict is 6 of 9 boundaries PASS — CAL_MATCH at 6.94e-18, LDA_SCORES at 4.84e-14, CAL_JSON; all pre-existing sub-ε / non-Stage-4 items) |
| stage5 | **PASS** | byte-equal on standardizer, subsample, svm_weights, percolator dumps cross-impl |
| stage6 | **PASS** | byte-equal on multicharge, consensus, reconciliation, rescored dumps cross-impl |
| stage7 | FAIL | 5474/5484 proteins differ on best_peptide_score (max diff 24.6) — see "Remaining: Stage 7" below |
| blib | NO_INPUTS | gated by stage7 freeze failing |

### Remaining: Stage 7 — protein FDR code divergence

After the parquet sort + Pearson + cosine alignments, we chased the
Stage 7 remainder. The Stage 6 → 7 boundary is now fully aligned:

* Both `1st-pass.fdr_scores.bin` sidecars: bit-equal (SHA
  `5ec0ccf4ce5fc111`, 27,768,152 bytes each side).
* Both `2nd-pass.fdr_scores.bin` sidecars: bit-equal (SHA
  `eba04f80558ba4bf`, 5,486,852 bytes each side) — this required
  taking option (a) from the earlier handoff: removing the
  `if has_reconciliation` gate at `pipeline.rs:5000` so Rust always
  persists the 2nd-pass sidecar. Landed as osprey `566f583`.
* Post-Stage-6 `.scores.parquet`: logically bit-equal (462,802 rows
  in identical physical order, identical entry_ids, identical
  protein_ids cross-impl, only the parquet writer's compression
  encoding differs file-size-wise).

**Yet Stage 7 still FAILs** with the same magnitudes as before — and
in fact the protein-set itself differs (Rust produces 5484 proteins,
C# 5485, with `sp|Q15283|RASA2_HUMAN` only on the C# side). Since
all upstream inputs are now provably bit-equal at the byte level, the
remaining divergence is **inside Stage 7's protein-FDR / parsimony /
score-selection code**, not in what it reads.

This is the next investigation, not closable in this overnight push:
the two impls' protein FDR ports diverge on either (i) which entries
feed the parsimony graph (different gate / filter conditions), (ii)
how parsimony groups are built (different iteration order, different
set-cover policy in non-Razor modes), or (iii) how "best peptide
per protein" is selected (different score-source preference or
tiebreak). The score diffs are large (24+ score units, q-values
flipping across [0,1]) so a small ULP-style alignment isn't the
explanation — this is genuine code divergence.

### Per-side state at end of Option A push

| Stage | Per-side gate | Pre-Option-A | Post-Option-A |
|---|---|---|---|
| stage1to4 | Test-Regression 1e-9 | PASS | PASS |
| stage5 | byte-equal 4 dumps | FAIL (catastrophic) | **PASS** |
| stage6 | byte-equal 4 dumps | FAIL (cascade) | **PASS** |
| stage7 | per-column 1e-9 | FAIL | FAIL (now isolated to Stage 7 code itself, all inputs proven bit-equal) |
| blib | per-table tolerance | NO_INPUTS | NO_INPUTS (gated by stage7) |

Stages 1-6 inclusive now pass per-side bit-equal cross-impl with no
information sharing on net8.0 Stellar Single. That's the through-line
the user explicitly asked for — the standardizer-to-percolator-to-
rescored cascade that previously fanned out across every dump is now
fully closed.

### Commits this round (cumulative)

| Repo | Commit | Content |
|------|--------|---------|
| osprey | `8dc0441` | compute_cosine_at_scan single-pass + sorted parquet write |
| osprey | `566f583` | always persist 2nd-pass FDR sidecar (single-file too) |
| pwiz | `9a72565527` | PearsonCorrelationRaw moment form + sorted parquet write |
| ai | `42b60a7` | Test-Regression-Hybrid + Test-Regression-RustFeed variants |

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260516_ospreysharp_wsl_parity-option-a.md`. The
Stage 1-6 per-side bit-equal floor is in place. The next natural
target is the Stage 7 protein-FDR / parsimony cross-impl divergence,
which the harness now isolates cleanly (every Stage 7 input is
proven bit-equal cross-impl, so any work happens entirely inside
Stage 7 code).

## Postscript 10 — Stellar Single straight-through + Stellar 3-file (2026-05-21)

Continued from the Option A overnight result, working through the
three modes of cross-impl test on Stellar.

### Stellar Single, straight-through (no rehydration): PASS

The straight-through path (each side runs its own full pipeline in
memory with no sidecar boundary, no information sharing) now bit-
equals cross-impl end-to-end on Stellar Single net8.0:

* Stage 7 protein FDR dump: every column PASS at 1e-9, 0 diverging rows
* Blib content: every table column PASS, 0 diverging rows
* `OVERALL: PASS — Rust and C# end-to-end in-memory bit-parity at
  1e-9 on Stellar 1-file`

Root cause was one missing sort: Rust's `deduplicate_pairs` ends with
`sort_by_key(|e| e.entry_id)` (osprey `pipeline.rs:6123`) with an
explicit comment about "non-deterministic gradient updates and model
weights." The C# port's `DeduplicatePairs` was returning entries in
`Dictionary.Values` insertion order. The rehydration path masked this
because entries loaded from the canonically-sorted parquet, but the
straight-through path fed un-sorted entries straight to Percolator,
producing ~190-precursor / ~270-peptide first-pass FDR drift on
Stellar Single. Pwiz `d85a3cbad7`.

### Stellar 3-file: stages 1-6 PASS, Stage 7 still drifts

The 3-file case (where reconciliation actually runs across replicates)
exposed two more divergences. The first one was fixed; the second is
in progress.

**Fixed: ConsensusRts decoy pairing.** C#'s consensus selection in
`OspreySharp.FDR.Reconciliation.ConsensusRts.Compute` identified
paired decoys by stripping the `DECOY_` prefix from the modified
sequence. Rust pairs by `base_id` (`entry_id & 0x7FFFFFFF`) per the
explicit comment in `reconciliation.rs::compute_consensus_rts`:

> "Pairing was already established by the FDRBench manifest or
> composition fallback during library load. The prefix-strip approach
> only works for Osprey-generated decoys; it silently misses library-
> supplied decoys (Carafe etc.) whose modified sequence carries no
> prefix."

On Stellar 3-file, prefix-strip leaked 16 extra decoys into the
cross-file consensus output. With base_id pairing, the consensus,
reconciliation, and rescored dumps are all now bit-equal cross-impl
(Stage 6 PASS per-side). Pwiz `c250ae351f` (consensus piece).

**In progress: 2nd-pass Percolator divergence on multi-file.** Stage 7
still fails on 3-file: Rust 5360 protein groups vs C# 6541 in the
dump; C# `detected_peptides` at experiment_precursor_q ≤ 0.01 has
44924 unique peptides vs Rust's 21120. Pattern:

* Post-Stage-6 `.scores.parquet` is bit-equal cross-impl (same 463358
  rows in identical physical order, same `entry_id`s, same feature
  values byte-for-byte in the first-5 row spot check).
* Stage 6 `rescored.tsv` is bit-equal cross-impl (carries
  `experiment_precursor_q` column; PASS in the per-stage comparator).
* The `.2nd-pass.fdr_scores.bin` sidecars written AFTER the rescored
  dump have the **same byte size** cross-impl but **different SHAs**
  and different `score` values per entry (entry 0 file 20: Rust 0.397
  vs C# 2.505). So the 2nd-pass Percolator runs after the rescored
  dump is captured and produces divergent SVM output cross-impl.

Tried a fix: sort `per_file_entries` by `entry_id` at the top of
`run_percolator_fdr` on both sides (mirrors the `deduplicate_pairs`
sort) so the SVM working-set selection sees canonical order
regardless of gap-fill append position. Result: Rust dump shifted
5372 → 5360 (small change); C# unchanged. Did not close the gap.
Rust `cf32a3d`, pwiz piece in `c250ae351f`.

The remaining drift isn't input order. Candidates for the next
investigation:

* SVM training subsample selection / fold split. The 1st-pass
  Percolator runs on the full 1.4M entries (subsampled to 300K). The
  2nd-pass runs on the 393K post-compaction pool — both sides feed
  identical post-rescore parquets, but the subsample/fold logic may
  use a per-side-different iteration over the (best-per-precursor +
  per-peptide-grouped) training set.
* Whether C#'s `RunPercolatorStreaming` path is taken for 3-file. The
  393K entry count is above the 300K subsample target but probably
  below the streaming threshold (max_train_size * 2 = 600K). Both
  sides likely take the direct path. Worth verifying logs.
* `ComputeExperimentPrecursorQvalues` on each side: the q-value
  propagation by base_id might differ in detail. Rust's
  `osprey-fdr/src/percolator.rs:2168` is the explicit comparison
  point for C#'s `OspreySharp.FDR.PercolatorFdr.cs:1783`.

### Mode summary on Stellar (where we are now)

| Mode | net8.0 | Status |
|---|---|---|
| Per-side rehydration, Stellar Single | PASS through blib | Option A complete (overnight) |
| Straight-through in-memory, Stellar Single | PASS through blib | Closed by `DeduplicatePairs` sort |
| Per-side rehydration, Stellar 3-file | Stages 1-6 PASS, Stage 7 FAIL | 2nd-pass Percolator on multi-file diverges |
| Straight-through in-memory, Stellar 3-file | Stages 1-? PASS, Stage 7 FAIL | Same root cause as per-side |

### Commits this round (cumulative)

| Repo | Commit | Content |
|------|--------|---------|
| pwiz | `d85a3cbad7` | DeduplicatePairs sort by EntryId (closes Stellar Single straight-through) |
| ai | `2f79dd1` | Compare-EndToEnd-Crossimpl -Framework / -Files switches + precursor regex |
| osprey | `84ff72c` | `OSPREY_DUMP_DETECTED_PEPTIDES` diagnostic dump for cross-impl bisection |
| osprey | `cf32a3d` | Sort per_file_entries by entry_id at run_percolator_fdr entry |
| pwiz | `c250ae351f` | ConsensusRts pair decoys by base_id + sort Percolator input |

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260516_ospreysharp_wsl_parity-option-a.md` (last
updated for Option A overnight; remains valid since this postscript
extends the same work). The immediate target is the 3-file Stage 7
divergence above. Two diagnostic commits sit ready: the Rust
`OSPREY_DUMP_DETECTED_PEPTIDES` dump (`84ff72c`) and its C# twin (in
`d85a3cbad7`-era code) for cross-impl bisection.

## Postscript 11 — 3-file Stage 7 dedup investigation (2026-05-21)

Dug into the 3-file Stage 7 cross-impl divergence under user
direction. Two new commits landed; the underlying SVM-training
divergence on 3-file remains open.

### Algorithmic find: missing best-per-precursor dedup in Rust direct path

The Rust streaming Percolator path (`pipeline.rs:5512-5557`) runs a
best-per-precursor dedup before peptide-group subsampling so the SVM
trains on one observation per precursor instead of N observations per
N-file experiment. The Rust direct path (`osprey-fdr/src/percolator.rs::
run_percolator`) was written without that dedup. The C# port's direct
path (`OspreySharp.FDR.PercolatorFdr.RunPercolator`) had already
inferred the correct dedup-then-subsample shape and was statistically
correct.

User confirmed this as an algorithmic mistake on the Rust side ("Mike
made an algorithmic mistake; Claude assumed the correct
implementation and so failed to match the Rust bug of training on
duplicates"). Patched Rust to mirror the streaming path's dedup —
both implementations now train on the same dedup'd 131k entries on
Stellar 3-file (vs. Rust previously training on the full 393k pool
with multi-file repeats inflating apparent target/decoy separation).
Osprey `8ef6aa6`; pwiz `fa9b2cbe94` (comment refresh, code unchanged).

### Stage 7 still drifts on 3-file

With dedup aligned, both sides feed the 2nd-pass Percolator the same
131,425-entry training set (66,857 targets + 64,568 decoys) in the
same sorted order. Yet the resulting `.2nd-pass.fdr_scores.bin`
sidecars have identical sizes but different SHAs cross-impl, and
Stage 7 still reports Rust 5,366 protein groups vs. C# 6,541.

Per-fold training counts also match (Rust logs 87,645 / 87,485 /
87,720 train per fold; C# fold split logic is the same round-robin
peptide-grouped algorithm). The remaining drift is somewhere inside
the SVM solver or Percolator iteration logic on the same input —
candidates we have not yet diagnosed:

* SVM solver iteration count differs sharply (C# 2nd-pass converges
  at 6-7 Percolator iterations per fold; Rust runs to its 10 cap
  with many inner SVM convergences per fold). Could be different
  outer-iteration convergence criterion.
* Inner SVM solver may use slightly different stopping condition or
  numerical tolerance.
* `decoyScores.Sort()` for median computation is unstable but values
  are unique in practice; existing `Array.Sort` callsites are vetted
  with explicit tie-impossible comments.

### Diagnostic dump that would resolve this

Both sides have `OSPREY_DUMP_SUBSAMPLE=1` env-var support that writes
a per-entry `entry_id, native_position, charge, modified_sequence,
is_decoy, base_id, in_subsample, fold_id` TSV. The 2nd-pass call
overwrites the 1st-pass dump (same filename), so the final TSV on
disk captures the 2nd-pass training state. A `Test-Regression`
re-run on the 3-file workdir with this env var set would emit
`rust_stage5_subsample.tsv` and `cs_stage5_subsample.tsv` (the
filename remains "stage5_" even for the 2nd-pass call). Diffing them
shows whether the subsample SET or the fold assignment differs
cross-impl. (Tried a quick direct-binary run on a copied workdir;
hit a parquet library_hash mismatch — needs a full Test-Regression
run to bypass.)

### Commits this round (cumulative)

| Repo | Commit | Content |
|------|--------|---------|
| osprey | `8ef6aa6` | best-per-precursor dedup in direct-path Percolator (matches streaming + C# behavior) |
| pwiz | `fa9b2cbe94` | comment update on C# direct-path dedup (no code change) |

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260516_ospreysharp_wsl_parity-3file.md`. The
immediate diagnostic to run is the 3-file Test-Regression with
`OSPREY_DUMP_SUBSAMPLE=1` and compare the per-side subsample TSVs
post-2nd-pass to localize whether the divergence is the training
set, the fold assignment, or downstream SVM/Percolator logic. The
earlier handoff `handoff-20260516_ospreysharp_wsl_parity-option-a.md`
remains a valid startup reference for the underlying sprint setup
but is superseded by this one for current state.

## Postscript 12 — 3-file Stage 7 bit-equal PASS (2026-05-21)

Walked the bisection ladder from the postscript-11 handoff state and
landed Stage 6 + Stage 7 bit-equal on 3-file Stellar. Three coupled
defects accounted for the entire remaining divergence.

### Bisection: where the ladder stopped

* **Ladder L1 (standardizer dump)**: differed by 1 ULP on `rt_deviation`
  mean. Per-column `perc_input` diff localized to (a) 2275 ULP-phantom
  string-formatting differences in `peak_apex` (same f64 bits, two
  equally-valid 16-digit roundtrip representations -- not real
  divergence), and (b) 280 real diffs in `rt_deviation` / mirror
  `abs_rt_deviation` -- traced to 94 per-file groups of duplicate
  `(entry_id, charge, scan_number)` rows where the two distinct values
  appeared in swapped order across sides.
* **Ladder L4 (tie-break instability)**: confirmed. The canonical sort
  added in postscript-11 was `(entry_id, charge, scan_number)`. Those
  three keys tie on the duplicate-key rows, and .NET `List<T>.Sort` is
  unstable, so the same input produced swapped order at every tied
  group. Did NOT need to bisect into the SVM solver (ladder L3).

### Three root causes

1. **Sort key needs a fourth tie-breaker.** Adding `parquet_index` as a
   final tie-break in both `pipeline.rs::run_percolator_fdr` and
   `FirstJoinTask.cs::RunPercolatorFdr` makes the total order identical
   on both sides regardless of underlying sort stability, because the
   per-side parquets are byte-equal and `parquet_index` references the
   shared canonical row layout.

2. **Gap-fill `parquet_index` not remapped after canonical sort.** The
   parquet writer's internal sort moves rows but `FdrEntry` stubs kept
   their pre-sort `parquet_index`. Next Percolator pass loaded features
   from the wrong row. Fix: compute the canonical permutation
   explicitly in `rescore_per_file_loop`, invert into pre->post indices,
   and remap every stub (upstream rows by `pre_to_post[old_pq_idx]`,
   gap-fill stubs via a new `vec_idx -> pre_sort_row` map built during
   append). Applied in Rust; the C# port already remapped correctly.

3. **`compute_experiment_precursor_qvalues` didn't propagate.** The
   Rust direct path only assigned the q-value to the single
   `compete_all` winner per `base_id`, leaving every non-winning
   per-file observation at `q=1.0`. The streaming path already did the
   right thing (`base_id_exp_prec_q` map) and the C# port matched
   streaming. Fixed Rust direct path to build the same map and
   propagate. Net effect on the diagnostic: 109K `exp_prec_q` diffs
   per file went to zero.

4. **C# PSM Id collision.** OspreySharp constructed `psm_id` as
   `"{fileName}_{EntryId}"`. EntryId is NOT unique within a file: a
   single `base_id` with multiple scan-time observations (different
   `scan_number`, same charge, same modified_sequence) shares one
   EntryId. The 2-component psm_id collided on those, so `resultMap`
   last-wins copied one observation's Percolator result onto every
   same-EntryId stub. Rust direct path used a 4-component id
   `"{file}_{mod_seq}_{charge}_{scan}"`; C# now matches.

### Files changed + commits

| Repo | Commit | Content |
|------|--------|---------|
| osprey | `8712ffe` | parquet_index sort tie-break + gap-fill remap + exp_prec_q propagation + `dump_stage5_perc_input` diagnostic |
| pwiz | `bfd52e0095` | C# 4-component psm_id + ParquetIndex sort tie-break + perc_input dump + subsample dump native_position tie-break |
| ai | `dd8d524` | stage6 envVars add standardizer + perc_input + subsample + svm_weights dumps + PERC_INPUT/_ONLY hooks added to defensive clear list |

### Stage 6 + Stage 7 PASS evidence

```
pwsh -File 'C:/proj/ai/scripts/OspreySharp/Test-Regression.ps1' \
     -Dataset Stellar -Files All \
     -StartStage stage6 -StopAfterStage stage7 \
     -Tag perside_3file_v4

--- stage6 ---
  [run] rust stage6    exit=0 wall=03:01
  [run] cs   stage6    exit=0 wall=03:57
  [PASS] stage6
  [freeze] inputs prepared for stage7

--- stage7 ---
  [run] rust stage7    exit=0 wall=00:06
  [run] cs   stage7    exit=0 wall=00:10
  [PASS] stage7
```

Per-file `.2nd-pass.fdr_scores.bin` SHAs cross-impl are bit-equal on
all 3 files; `diff_fdr_bin.py` reports 0 score / q-value diffs.

### Latent / follow-up items

* **Parquet rewrite leaves empty fragment lists for ~73K gap-fill
  entries in C#**: still UNFIXED. C# stage 6 writes the rewritten
  `.scores.parquet` with empty `fragment_mzs` /
  `reference_xic_rts` / `fragment_intensities` for ~73K gap-fill rows;
  Rust populates them. Accounts for ~85 MB parquet-size delta. Does
  NOT affect 2nd-pass training (PIN feature scalars are populated)
  and was deliberately left out of this fix. Track separately.
* **`peak_apex` / `xcorr` perc_input dump formatting** still emits
  2280 phantom diffs that have bit-identical f64 representations.
  The two sides' shortest-roundtrip search finds equally-valid 16-
  digit prints. Could be normalized (always use the same digit count)
  if a future bisection workflow needs raw `diff` to be clean. Not
  urgent.
* **Duplicate-`(file, mod_seq, charge, scan_number)` PercolatorEntry
  collisions** (94 per file on 3-file Stellar) still happen. Both
  sides now consistently last-wins on the same observation, but the
  underlying algorithmic question -- whether two scan observations
  with the same key but different `rt_deviation` should be scored
  separately or merged upstream -- is open. Cross-impl parity does
  not depend on the answer.

## Postscript 13 — Stellar 3-file perf refresh + WSL Linux binaries (2026-05-21 evening)

After postscript-12 landed Stellar 3-file straight-through bit-equality,
this session refreshed the Stellar timing tables in
`Osprey-workflow.html` (pwiz commit `3b04664509`) and rebuilt Linux
binaries from the post-fix commits.

### Phase B: Compare-EndToEnd-Crossimpl 3-file Stellar straight-through PASS

```
pwsh -File ./scripts/OspreySharp/Compare-EndToEnd-Crossimpl.ps1 \
     -Dataset Stellar -Files All -Framework net8.0 -Force

[Rust]     wall 04:13   precursors 59733   blib 52310016 bytes
[C#]       wall 04:43   precursors 59733   blib 52494336 bytes
Stage 7 protein FDR (per-col 1e-9):  PASS
Blib content (SQL row+col 1e-9):     PASS
OVERALL: PASS  --  bit-parity at 1e-9 on Stellar 3-file
```

### Phase C: WSL Linux binaries (Ubuntu 22.04)

* Rust: `cargo build --release` via `~/.cargo/bin/cargo` (1.95.0).
  Toolchain pin needed because system `/usr/bin/cargo` is 1.75.0 and
  doesn't support `edition2024` (required by `base64ct 1.8.3`).
  Output: `/mnt/c/proj/osprey/target/release/osprey` (15.9 MB ELF).
* C#: `dotnet publish -r linux-x64 --self-contained -c Release -f net8.0`.
  Output: `bin/Release/net8.0/linux-x64/publish/OspreySharp`.
  Measure-Pipeline.ps1 uses the cross-platform launcher at
  `bin/x64/Release/net8.0/OspreySharp` (72 KB), which loads the
  refreshed `.FDR.dll` from the same directory (today's fixes).

### Phase D: Measure-Pipeline Stellar 3-file × 4 cells × 1 repeat

| Config | Total wall | Notes |
|---|---|---|
| Rust  Windows | 4:29 | stage5 1:16, stage1to4 1:42 |
| C#    Windows | 4:39 | stage5 2:03, stage1to4 1:20 |
| Rust  WSL     | 6:01 | stage5 1:05, stage1to4 3:11 |
| C#    WSL     | 6:39 | stage5 2:12, stage1to4 2:46 |

* Windows ratio C#/Rust = 1.04x (~tied)
* WSL ratio C#/Rust = 1.11x (Rust faster by ~10%)
* stage5 (Percolator SVM training) is the dominant C# slowdown on
  both OSes -- worth a future targeted pass.
* WSL stage1to4 nearly 2x slower than Windows for both impls
  (9P-mzML reads dominate); not a regression -- existing artifact.

Artifacts:
* `ai/.tmp/measure-pipeline/stellar-3file-windows-20260521/report.md`
* `ai/.tmp/measure-pipeline/stellar-3file-wsl-20260521/report.md`

### Phase E: Osprey-workflow.html refresh (pwiz `3b04664509`)

Both the Windows-native and WSL Linux tables now carry today's
Stellar 3-file numbers. Astral columns untouched (no Astral
re-measurement this session). Annotation calls out that the Stellar
refresh post-dates the 3-file straight-through bit-equality and lists
the relevant osprey/pwiz commits.

### Open follow-ups for next session

1. **Stellar 3-file → median-of-3** (currently 1-shot per cell, the
   stopping point we committed to). Re-run `Measure-Pipeline.ps1
   -Repeats 3` per OS for tighter intervals.
2. **Astral 3-file bit-equality** -- not addressed today; still on
   the original 2026-05-18 numbers.
3. **C# 73K gap-fill empty-fragment parquet** (postscript-12 follow-up
   item) -- still UNFIXED. Does not affect parity but causes 85 MB
   parquet-size delta on 3-file Stellar.
4. **stage5 C# perf gap** -- ratio is 1.61x Windows / 2.01x WSL.
   Worth a targeted pass; might also help Astral.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260516_ospreysharp_wsl_parity-postperf.md` before
starting work.

## Postscript 14 — Astral parity probe + WSL slowdown puzzle (2026-05-21 late evening)

Continued same session after postscript 13. Ran two more parity gates
and surfaced a perf regression worth investigating overnight.

### Astral 1-file straight-through PASS

```
pwsh -File ./scripts/OspreySharp/Compare-EndToEnd-Crossimpl.ps1 \
     -Dataset Astral -Files Single -Framework net8.0 -Force

[Rust]     wall 07:51   precursors 137129   blib 92917760 bytes
[C#]       wall 06:13   precursors 137129   blib 93380608 bytes
Stage 7 protein FDR (per-col 1e-9):  PASS
Blib content (SQL row+col 1e-9):     PASS
OVERALL: PASS  --  bit-parity at 1e-9 on Astral 1-file
```

C# 21% faster on Astral 1-file (HRAM); a different balance than
Stellar 3-file (~tied). Confirms today's bit-equality fixes did NOT
regress Astral 1-file.

### Astral 3-file straight-through — MIXED

```
pwsh -File ./scripts/OspreySharp/Compare-EndToEnd-Crossimpl.ps1 \
     -Dataset Astral -Files All -Framework net8.0 -Force

[Rust]     wall 23:15   precursors 165573   blib 134647808 bytes
[C#]       wall 21:58   precursors 165573   blib 135208960 bytes
Stage 7 protein FDR (per-col 1e-9):  FAIL  (group_qvalue max_diff 1.1e-4, 177/13087 rows)
Blib content (SQL row+col 1e-9):     PASS
OVERALL: FAIL  --  technically FAIL per script, but BLIB IS BIT-EQUAL
```

* `best_peptide_score`: PASS (max_diff 2.2e-13, essentially bit-equal)
* `n_unique` / `n_shared` / `is_target_winner`: PASS (categorical)
* `group_qvalue`: FAIL — 177/13087 rows differ by up to 1.1e-4
* `.blib` content: PASS at 1e-9 (downstream consumer is unaffected)

So the residual is **q-value-only** drift in protein FDR; downstream
parquet/blib are bit-equal. Wall-clock perf: Rust 23:15, C# 21:58
(1.06x ratio, close to historical 2026-05-18 numbers).

### WSL stage1to4 slowdown vs Windows on Stellar — new regression

Today's Stellar 3-file numbers:

| Stage1to4 | Windows | WSL | ratio (WSL/Win) |
|---|---|---|---|
| Rust | 1:42 | 3:11 | 1.87x slower |
| C# | 1:20 | 2:46 | 2.08x slower |

But the **2026-05-17/05-18 baselines** had WSL **FASTER** than Windows
on stage1to4 (Rust 1:46 WSL vs 1:54 Win; C# 1:11 WSL vs 0:59 Win was
about the only exception). The original WSL ext4 was on the C: SSD via
`%LOCALAPPDATA%\wsl\ext4.vhdx`; the test data store may have moved to
D: HDD between then and now, which would explain why mzML reads
(stage1to4's dominant cost) got slower.

This is unexpected and worth a deeper look overnight.

## Open follow-ups for next session

1. **Astral 3-file group_qvalue residual** (1.1e-4 on 177/13087 rows) —
   likely a float-summation order in protein FDR's monotonic q-value
   pass. Bit-equal everywhere else; blib unaffected.
2. **Astral 3-file perf refresh** (4 cells) — blocked on (1).
3. **WSL stage1to4 slowdown investigation** — characterize per-substage
   (mzML read vs scoring vs serialize), test SSD-vs-HDD hypothesis by
   relocating WSL VHDX from D: back to C:.
4. **Stellar 3-file → median-of-3 + Astral median-of-3** — current
   timings are 1-shot per cell.
5. **C# 73K gap-fill empty-fragment parquet** (postscript-12 follow-up).
6. **stage5 C# perf gap** — 1.61x Windows / 2.01x WSL vs Rust.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260516_ospreysharp_wsl_parity-astral-perf.md` before
starting work.

---

## Postscript 17 (2026-05-23) — Astral 3-file root cause + Bucket-3 split + integration test PASS

### Astral 3-file group_qvalue ROOT CAUSE: decoy gap-fill duplication

Bisected the residual 1.1e-4 divergence on 177/13087 rows with a
chain of new dumps (`OSPREY_DUMP_DETECTED_PEPTIDES`,
`OSPREY_DUMP_STAGE7_WINNERS`, `OSPREY_DUMP_BEST_PEPTIDE_SCORES`).
Localized to 407 decoy modseqs having different aggregated max
scores cross-impl despite bit-equal sidecar scores per entry_id.

Root cause: **reconciliation gap-fill was including
`decoy_entry_id` in `gap_fill_ids`** (pipeline.rs ~3080) alongside
`target_entry_id`. Every decoy already has a row in the 1st-pass
parquet (decoys are scored against every spectrum). Gap-fill then
appended an exact-duplicate parquet row (same entry_id+charge+
scan_number+apex_rt) with a different score (1st-pass natural-RT
vs gap-fill forced-RT). `collect_best_peptide_scores` took max
over the duplicates, inflating `decoy_score` per protein group,
shifting cumulative-FDR sort positions, and producing the 1.1e-4
`group_qvalue` divergence.

OspreySharp had the same bug but its `Dictionary<uint, FdrEntry>`
sidecar overlay deduplicated one of the two via key overwrite —
masking the bug from one side. So both sides were buggy in
mirror-image ways, with the visible cross-impl drift falling out
of the asymmetry.

**Fix** (commit `d77ffec`, now PR #45): drop `decoy_entry_id` from
`gap_fill_ids`; targets continue through gap-fill as before.
Astral 3-file post-fix: byte-equal blib + Stage 7 protein FDR
PASS at 1e-9. Precursor count: 165,573 → 167,285 (+1,712), since
targets are no longer depressed by inflated `decoy_score`
aggregations.

Remaining target-favoring asymmetry: targets get cross-replicate
consensus RT via gap-fill, decoys don't get equivalent. The
principled fix (per-decoy consensus RT) needs Mike's predicted-
decoy-spectra/RT libraries. In the meantime this PR stops
aggravating the asymmetry.

### Bucket-3 PR split — 6 new PRs on maccoss/osprey

Split PR #37 (16-commit epic) + post-merge bit-parity work into
focused, separately-reviewable PRs. Pattern per PR: Copilot
review → fix → fresh-context Claude agent review → fix →
squash-merge. Full loop done for #38 + #39 (both MERGED) and the
first iteration done for #40 (Copilot + agent fixes pushed,
threads resolved).

| PR | Theme | State |
|---|---|---|
| #38 | Bucket 1 diagnostics | MERGED (`41894f4`) |
| #39 | Bucket 2 ULP-scale bit-parity tweaks | MERGED (`0f5433e`) |
| #40 | Bucket 3a HPC chain `--join-at-pass=2` correctness | OPEN |
| #41 | Bucket 3b non-ppm precursor tolerance MS1 default | OPEN |
| #42 | Bucket 3c Calibration pass 2 LOESS+metadata refresh | OPEN |
| #43 | Bucket 3d Percolator sort + dedup + parquet_index remap | OPEN |
| #44 | Bucket 3e LDA-side-effect re-sort + ms2_cal_errors diag | OPEN |
| #45 | Bucket 3f Decoy gap-fill exclusion (the closer) | OPEN |
| #37 | original 16-commit epic | DRAFT, awaiting close |

pwiz PR #4233 (ProteoWizard/pwiz) has all C# mirror changes
(decoy gap-fill exclusion, fail-fast on missing mzML cvParams,
diagnostic isolation refactor).

### Integration regression test — `test/integration-bucket3` branch

To validate the 6 splits don't cumulatively regress vs the
integrated state, built a single test branch from `origin/main`
+ merge each open PR branch + cherry-pick 3aca00c (LDA-sort +
ms2_cal_errors) + cherry-pick d77ffec (decoy gap-fill). Zero
merge conflicts. 528 Rust + 344 C# tests pass (872 total).

**Stellar 3-file end-to-end PASS at 1e-9 vs OspreySharp.**
Astral 3-file run killed mid-execution (resource competition);
needs re-launch overnight.

### New diagnostic infrastructure + documentation

- `osprey-fdr/src/diagnostics.rs` new module (in PR #38, merged)
- `dump_stage7_winners` + `dump_best_peptide_scores` + their
  `*_enabled()` predicates for caller-side short-circuit
- C# mirror: `OspreySharp.FDR/FdrDiagnostics.cs`
- `dump_ms2_cal_errors` Rust side bundled with PR #44
- `ai/scripts/OspreySharp/DIAGNOSTICS.md` — comprehensive
  reference doc cataloging every `OSPREY_DUMP_*` env var across
  both impls, grouped by pipeline stage, with matching
  `cs_*`/`rust_*` filename, source location, and when-to-use
  guidance. Pushed to pwiz-ai master.

### Open follow-ups for next session

1. **Astral 3-file integration test on `test/integration-bucket3`** —
   re-launch overnight. PASS at 1e-9 confirms the splits compose
   correctly. FAIL → bisect by reverting merges in reverse order.
2. **Copilot reviews on PRs #41 – #45** — same cycle as #40:
   Copilot summary → fix → resolve threads → fresh-context Claude
   agent review → fix → approve.
3. **Squash-merge approved PRs** (one focused commit per PR).
4. **Close PR #37** with a comment linking to the 6 split PRs
   once #45 has landed.
5. **Address Copilot review on pwiz PR #4233** as Rust side lands.
6. **Final perf cells** — 8 cells (Stellar+Astral × Rust+C# ×
   Windows+WSL) after merge.
7. **WSL stage1to4 slowdown investigation** (carry-over from
   postscript 16).
8. **Median-of-3 perf timings** instead of 1-shot per cell
   (carry-over).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260523_bucket3_pr_pipeline.md` before starting
work.

---

## Postscript 18 — 2026-05-24 autonomous night session

Three deliverables on the user's overnight plate: verify Astral
parity on `test/integration-bucket3`, run a WSL SSD-vs-HDD I/O
bench, refresh the 8-cell perf table in `Osprey-workflow.html`.
All three completed.

### 1) Astral 3-file integration bit-equality — PASS

Ran `Compare-EndToEnd-Crossimpl.ps1 -Dataset Astral -Files All
-Framework net8.0 -Force` on the integration branch (osprey HEAD
`8262381`, pwiz HEAD `89995c95e1`). Walls: Rust 26:46, C# 24:37.
167,285 precursors each side, **Stage 7 protein FDR PASS at 1e-9
per-column**, **blib content PASS at SQL row+col 1e-9** (blib
size delta 577 KB = SQLite freelist; row content bit-equal). The
straight-through cross-impl gate now holds on both Stellar and
Astral on the integration branch.

Log: `ai/.tmp/integration-test-astral-20260523-2311.log`.

### 2) WSL I/O bench — SSD-vs-HDD confirmed; VHDX is on HDD

Direct `dd`-based bench (write `fdatasync` + read `O_DIRECT`
+ 500×4 KiB fsync metadata) across four WSL targets:

| Target       | Backing storage         | Seq write  | Seq read¹   | 500×4 KiB fsync |
|--------------|-------------------------|-----------:|------------:|----------------:|
| `/mnt/c`     | C: SSD via 9P drvfs     |  333 MB/s  |  445 MB/s   |   240 files/s   |
| `/mnt/d`     | D: HDD via 9P drvfs     |  180 MB/s  |  476 MB/s¹  |    23 files/s   |
| `/home`      | ext4 / VHDX / D: HDD    | 1787 MB/s² | 10716 MB/s¹ |    14 files/s   |
| `/dev/shm`   | tmpfs (RAM)             | 2929 MB/s  |     —       |   671 files/s   |

¹ Cache-influenced (4 GiB fits in NTFS / page cache on a 64 GB
host). ² fdatasync flushes Linux dirty pages but not the
Windows-side VHDX cache.

**Important finding:** `D:\test\wsl\{guid}\ext4.vhdx` — the
distro's ext4 lives on the *HDD*, contradicting the workflow doc
claim of `%LOCALAPPDATA%\wsl\` (SSD). At some point between
2026-05-18 and 2026-05-24 the WSL distro was relocated to D:.
This is the root cause of WSL Astral Rust stage1to4 jumping from
6:07 (2026-05-18) to 19:38 (2026-05-24) on the same hardware
(see perf table).

Full writeup: `ai/.tmp/wsl-io-bench/summary.md`.

**Per-substage timing within stage1to4** (mzML read vs scoring
vs serialize) is *not* available from the current Rust binary —
only the five `[STAGE-WALL]` markers exist. The I/O bench plus
the stage-level perf table together already pin down the disk
asymmetry; finer instrumentation is left as a separate follow-up.

### 3) 8-cell perf table — Windows + WSL refreshed

Ran `Measure-Pipeline.ps1 -Dataset Both -Tool Both -Repeats 1`
separately on Windows-native pwsh and WSL pwsh. Reports under
`ai/.tmp/measure-pipeline/`.

| Dataset | OS      | Rust total | C# total |
|---------|---------|-----------:|---------:|
| Stellar | Windows |     5:04   |   3:52   |
| Stellar | WSL     |     6:10   |   5:33   |
| Astral  | Windows |    25:34   |  20:09   |
| Astral  | WSL     |    31:41   |  23:55   |

Notable shifts vs prior baselines:
* **Windows Stellar Rust 4:29 → 5:04** (+0:35) — mostly stage1to4
  (+0:25) and small bumps in stage7 / blib. Single-run noise or
  small fixed cost from the PR #40-45 stack; without median-of-N
  can't yet say which.
* **Windows Astral C# 19:19 → 20:09** (+0:50) — stage1to4 +2:43,
  stage5 +2:36, stage6 −4:08. Stage6 acceleration matches the
  decoy-gap-fill exclusion fix (fewer entries to rescore);
  stage1to4 and stage5 increases warrant a second look post-merge.
* **WSL Astral Rust 16:12 → 31:41** (+15:29) — almost all in
  stage1to4 (6:07 → 19:38). Consistent with VHDX-moved-to-HDD;
  WSL is now ~2× slower than Windows on stage1to4, where it was
  previously similar or slightly faster.

The `Osprey-workflow.html` Windows and WSL tables are updated
with the new numbers and the WSL caveat block was rewritten to
include the I/O bench results table and correct the VHDX-location
claim. Committed locally on
`Skyline/work/20260516_ospreysharp_wsl_parity`; **not pushed**
(morning user can review then push).

### Carry-overs (still open for next session)

1. **Bucket 3 PRs #40-#45** — user wants to finalize tomorrow
   (review cycles + squash-merge + close PR #37).
2. **Median-of-3 perf timings** — the single-run table above has
   visible variance; a `-Repeats 3` refresh would tighten the
   numbers. Cheap to run (~3 hr unattended).
3. **WSL VHDX relocation to C: SSD** — bench predicts ~30-50%
   stage1to4 wall reduction. Destructive operation
   (`wsl --export`/`--import`), so flagged for explicit user
   sign-off, not done autonomously.
4. **Per-substage instrumentation inside stage1to4** — to
   localize the I/O contribution within the disk-bound stage.
   Small Rust change (~30 LOC).

Local commits (not pushed):
* `pwiz` Skyline/work/20260516_ospreysharp_wsl_parity:
  Osprey-workflow.html 2026-05-24 perf refresh + WSL caveat
  rewrite.
* `ai` master: this postscript 18.

**Session-end handoff**:
`ai/.tmp/handoff-20260523_night-session.md` captures the timeline
of the autonomous run with full diagnostic notes.

---

## Postscript 19 — 2026-05-24 day session (Rust regression + final perf)

After the night-session perf numbers landed, the user (now awake)
flagged the unexpected C#-beats-Rust pattern and asked for a
regression hunt + clean median-of-3 timings on the fastest available
storage. This postscript captures the rest of the day.

### 1) Rust perf regression — root cause + fix

Single-run bisection on Windows D: HDD (data set same, sum/n compiler
fix isolated):

| Build | Stellar Rust total | stage1to4 |
|---|---:|---:|
| `8712ffe` (PR #37 tip, 5/21 baseline) | 4:18 | 1:40 |
| `8712ffe` + Welford cherry-pick (`3aca00c`) | 4:42 | 2:01 |
| `5ad82d9` (integration: PR #40-43 merged, no Welford) | 4:40 | 2:03 |
| `8262381` (integration tip with Welford + decoy gap-fill) | 4:46 | 2:03 |

The Welford cherry-pick alone added +21 s on stage1to4. The original
commit message (`3aca00c`) had two motivations: (a) numerical
stability via a bounded running mean, and (b) defeating LLVM/.NET-JIT
vectorisation differences that produced 1-ULP mean drift cross-impl.
For ppm-scale MS2 calibration the (a) motivation never bites &mdash;
sum/n has ~9 digits of headroom at f64 precision. The (b) motivation
turned out not to require Welford either: with IEEE 754 strict mode
(Rust default, .NET default) prohibiting associative re-ordering of
the dependent reduction <code>sum = sum + x</code>, both compilers
fall back to serial scalar and produce identical results &mdash; once
the input order is pinned, which is what the deterministic
<code>(base_id, entry_id)</code> sort already in
<code>pipeline.rs</code> does.

**Fix landed locally on both repos:**
* osprey <code>b0c1f7e</code> on <code>test/integration-bucket3</code>:
  reverted Welford-Knuth to plain sum/n in
  <code>crates/osprey-chromatography/src/calibration/mass.rs</code>;
* pwiz <code>f9d873e39f</code> on
  <code>Skyline/work/20260516_ospreysharp_wsl_parity</code>:
  matching revert in
  <code>OspreySharp.Chromatography/MzCalibration.cs</code>.

Verified by re-running <code>Compare-EndToEnd-Crossimpl.ps1</code>:
both **Stellar PASS and Astral PASS at 1e-9** cross-impl on the
sum/n binaries (167,285 Astral precursors match, Stage 7 protein FDR
+ blib SQL row+col bit-equal). Rust Stellar perf recovered to 4:25,
within noise of the 4:18 baseline. C# Astral also saved ~2 min by
ditching its mirror Welford recurrence.

### 2) Storage fix — WSL VHDX relocated to C: SSD; data staged on C:

Pre-existing problem: D:\test was missing from Defender real-time
scan exclusions (user thought it was already excluded; it wasn't),
and the WSL <code>ext4.vhdx</code> had migrated from C: SSD to D: HDD
at some point. Both fixes applied this session:

* User added <code>D:\test</code> to AV-scan exclusions and created
  <code>C:\test</code> (also excluded) prior to authorising the work.
* Session relocated VHDX via <code>wsl --export</code> →
  <code>--unregister</code> → <code>--import</code> to
  <code>C:\wsl\ubuntu-22.04\ext4.vhdx</code>. Backup tar preserved
  at <code>C:\temp\wsl-ubuntu-22.04-backup.tar</code> until
  user confirms.
* Session staged Stellar (4.7 GB) and Astral (20 GB) test data on
  both <code>C:\test\osprey-runs</code> (Windows-native) and
  <code>/home/brendanx/test/osprey-runs</code> (WSL ext4).

Post-move I/O bench (raw <code>dd</code>): <code>/home</code> went
from 1185 MB/s → 2064 MB/s sequential write (now true C:-SSD speed
through the VHDX), <code>/mnt/c</code> stable at ~356 MB/s (drvfs
ceiling), <code>/mnt/d</code> back near its HDD ceiling at 215 MB/s.

### 3) Final median-of-3 perf — three configurations published

For each of the three viable on-SSD configurations, ran
<code>Measure-Pipeline.ps1 -Dataset Both -Tool Both -Repeats 3</code>:

| Config | Stellar Rust | Stellar C# | Astral Rust | Astral C# |
|---|---:|---:|---:|---:|
| Windows native NTFS on C: | 4:37 | 3:52 | 23:11 | 15:49 |
| WSL ext4 inside VHDX (<code>/home</code>) | **4:00** | 4:02 | **15:46** | 16:16 |
| WSL 9P drvfs (<code>/mnt/c</code>) | 6:09 | 5:59 | 24:03 | 24:55 |

The three medians-of-3 are now published in
<code>Osprey-workflow.html</code> as three stacked tables. Variance
is &lt;5 s on Stellar and &lt;90 s on Astral.

Headline cross-impl story per config:
* **Windows native:** C# 0.84&times; Stellar, 0.68&times; Astral
  &mdash; C# faster on every stage, dramatic on stage7+blib via
  skip-Percolator sidecar overlay.
* **WSL ext4 (/home):** Rust 17-21% faster &mdash; matches the
  historical Linux-native baseline and the user's recollection that
  Rust is faster on Linux ext4.
* **WSL 9P drvfs (/mnt/c):** Essentially tied (C#/Rust 0.97-1.04&times;)
  &mdash; the 9P penalty applies to both impls equally, so on the
  storage layout most users default to (data on Windows side, run
  pipeline from WSL shell), C# is at parity with Rust.

### Local commits (not pushed)

| Repo | Commit | What |
|---|---|---|
| osprey | <code>b0c1f7e</code> on <code>test/integration-bucket3</code> | Replace Welford with sum/n in calibration |
| pwiz | <code>f9d873e39f</code> on parity branch | Mirror Welford → sum/n in C# |
| pwiz | <code>307fb61683</code> on parity branch | Osprey-workflow.html refresh with median-of-3 |
| ai | (this commit, master) | Postscript 19 |

### Carry-overs for the team

1. **Land the Welford → sum/n revert as a focused osprey PR.** Lives
   only on <code>test/integration-bucket3</code> right now; needs a
   real upstream branch + PR + cross-impl gate via
   <code>Compare-EndToEnd-Crossimpl.ps1</code>.
2. **Bucket 3 PRs #40-#45.** Same plan as before; the sum/n revert
   either folds into one of them or ships as its own follow-up.
3. **Stage7 Rust skip-Percolator parity.** The big stage7 C# advantage
   in the Windows table comes from C# hitting the
   <code>FdrScoresSidecar</code> skip-Percolator path while Rust runs
   the full 2nd-pass SVM. The configurations measured here happen to
   leave Rust on the slow path; check whether the Rust skip is wired
   for the same cache state.
4. **VHDX backup cleanup.** Delete
   <code>C:\temp\wsl-ubuntu-22.04-backup.tar</code> (~31 GB) after
   verifying the new C: VHDX runs reliably for a few days.
5. **Push the local commits** when ready: pwiz parity branch has 2
   new commits (HTML refresh + sum/n revert); osprey integration
   branch is local-only by design (never push).
