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

## Current Status (2026-05-20 mid-day)

The Rust half of the coordinated f64 calibration flip is landed
(`osprey 690194a`). Per-column cal_match drift on Stellar Single:

| Column | Drift | Status |
|---|---|---|
| apex_rt | 0 | **bit-equal** ✓ |
| correlation | 4.97e-14 | f64 epsilon ✓ |
| libcosine | 5.55e-16 | f64 epsilon ✓ |
| xcorr | 3.876e-6 | **needs C# half (task #71)** |
| snr | 5.24e-10 | unchanged; separate root cause (LDA in-place mutation) |

The xcorr drift is the only remaining "headline" issue. Three options
for the C# half are documented in the most recent postscript; user
decision needed (task #71).

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



