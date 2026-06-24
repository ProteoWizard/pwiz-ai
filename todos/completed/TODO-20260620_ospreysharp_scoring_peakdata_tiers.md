# TODO-20260620_ospreysharp_scoring_peakdata_tiers.md

## Branch Information
- **Branch**: `Skyline/work/20260620_osprey_scoring_peakdata_tiers`
- **Base**: `master` (`a0065b3efa`, post-#4319 "retired AbstractScoringTask, debt-paydown PR 9")
- **Created**: 2026-06-20
- **Status**: Completed — [#4320](https://github.com/ProteoWizard/pwiz/pull/4320) (merged 2026-06-21 as 09269b4205)
- **Delivery**: ONE branch, THREE commits, ONE PR. Per the developer's preference,
  do not split into stacked PRs (sole developer on this code; well-separated, low
  merge-conflict risk). Open the PR after commit 1 so each subsequent pushed commit
  triggers TeamCity. Each commit is independently byte-parity + perf gated.

**Priority**: Medium-High — tightens the scoring SPI's encapsulation and materially
advances Skyline-portability of the score classes; touches the per-candidate hot loop
(perf-sensitive in commit 3).
**Type**: Architecture / scoring encapsulation. **Source**: `/pw-oop-review` of
`pwiz_tools/OspreySharp` (2026-06-20) + the scoring-phase follow-up discussion.
**Lineage**: builds on [[project_ospreysharp_byproduct_context_prc]] and the modular-
scoring sprint (`TODO-20260607_ospreysharp_modular_scoring`, PR #4277) and the
`CoelutionScorer` extraction (`TODO-ospreysharp_oop_review_findings` rec #1).

## Problem (from the OOP review)

The modular-scoring sprint gave each of the 21 PIN features its own calculator class
consuming a Skyline-shaped `IOspreyPeakData`/`IOspreyDetailedPeakData` — the CONSUMER
contract is clean and faithful to Skyline. Two gaps remain:

1. **No producer seam.** `CoelutionScorer.ScoreCandidate` (~590 lines,
   `CoelutionScorer.cs:157`) is BOTH the data-extraction service (scan-range select,
   XIC extraction, peak detection, apex/reference-XIC resolution) AND the calculator
   driver. In Skyline the restricted peak data is produced by a separate service and
   the scoring model only consumes it. The 12-arg `OspreyPeakData.Set(...)` hand-off
   (`:637-638`) is the symptom: nothing produces the peak data but this one method.
2. **Access is wider than needed.** Every calculator receives `IOspreyDetailedPeakData`,
   which exposes the whole isolation window's MS2 spectra (`WindowSpectra`) plus the
   window MS1 list (via the context) — far more than most features touch. There is no
   least-privilege boundary; a buggy/future calculator could read an arbitrary scan.

### Feature → data tier (the design driver; verified by reading all 8 families)
- **Summary** (scalars only — `Candidate`, `PeakBounds`, `ApexRetentionTime`,
  `ExpectedRt`): `rt_deviation` (11), `abs_rt_deviation` (12). **2 features.**
- **Detailed** (+ per-precursor `Xics`): coelution (0,1,2), peak-shape (3,4,5),
  median-polish (15,16,19,20) — and, AFTER commit 2 lifts MS1 production upstream,
  `ms1_precursor_coelution` (13) + `ms1_isotope_cosine` (14). **10 → 12 features.**
- **ApexSpectrum** (+ the single apex MS2 `Spectrum` + `ApexGlobalIndex`): `xcorr` (6),
  `consecutive_ions` (7), `explained_intensity` (8), `mass_accuracy_deviation_mean` (9),
  `abs_mass_accuracy_deviation_mean` (10). **5 features.**
- **ApexSpectra** (+ the apex±2 MS2 spectra): `sg_weighted_xcorr` (17),
  `sg_weighted_cosine` (18). **2 features.**

Outcome: 14 of 21 scores land in Summary+Detailed (the tier Skyline can already
provide), and only 7 genuinely need spectra Skyline does not yet expose at scoring
time — split into two honest levels above Skyline (one apex spectrum; five = apex±2).

**Reverses a locked modular-scoring decision.** That sprint locked "all 21 are
Detailed; no `SummaryOspreyFeatureCalculator` (would be dead)" and "MS1 is a spectral
family." Both are revisited here: rt-dev IS summary-only, and MS1 becomes a Detailed
XIC/vector consumer once its precursor XIC + isotope envelope are produced upstream.

## Plan (3 commits)

### Commit 1 — four-tier consumer contracts (behavior-free)
- Split `IOspreyPeakData` into the linear hierarchy
  `IOspreySummaryPeakData` ⊂ `IOspreyDetailedPeakData` ⊂ `IOspreyApexSpectrumPeakData`
  ⊂ `IOspreyApexSpectraPeakData` (mirrors Skyline `ISummaryPeakData`/`IDetailedPeakData`,
  then two levels above it). `Xics` moves to Detailed; `ApexSpectrum`/`ApexGlobalIndex`
  to ApexSpectrum; the window-spectra index members to ApexSpectra.
- Add `SummaryOspreyFeatureCalculator` / `DetailedOspreyFeatureCalculator` /
  `ApexSpectrumOspreyFeatureCalculator` / `ApexSpectraOspreyFeatureCalculator` bases,
  each narrowing the SPI's `IOspreySummaryPeakData` to its tier (same bridge pattern
  as today's `DetailedOspreyFeatureCalculator`). SPI signature becomes
  `Calculate(OspreyScoringContext, IOspreySummaryPeakData)`.
- Reclassify all 21 calculators to the narrowest tier they need (MS1 stays at the
  spectra tier in THIS commit — it still reads `context.Ms1Spectra`; it drops to
  Detailed in commit 2).
- `OspreyPeakData` implements the full `IOspreyApexSpectraPeakData`; update the test
  fake (`OspreyFeatureCalculatorsTest.FakeDetailedPeakData`) accordingly.
- Behavior-free → regression byte-identical by construction.

### Commit 2 — `PeakDataExtractor` owns ALL data production
- Extract scan-range selection (`FindScanRange`), XIC extraction, peak detection
  (`DetectCandidatePeaks` + fallbacks), best-peak ranking, apex/reference-XIC
  resolution out of `ScoreCandidate` into a `PeakDataExtractor` returning a populated
  `IOspreyApexSpectraPeakData` (+ the side artifacts `BuildFdrEntry`/CWT-capture need).
- **Lift MS1 production upstream**: the extractor produces the MS1 precursor-intensity
  XIC and the apex isotope envelope (the `FindNearest` sampling + `IsotopeEnvelope`
  work now inside the MS1 calculators) and hands them as data, exactly as Skyline
  produces MS1 chromatograms upstream. The two MS1 scores become pure consumers and
  reclassify to **Detailed** — the visible payoff of this commit. Preserve every
  MS1 parity trap (seed-0.0/`>=` ref-XIC pick, skip-not-zerofill, `<1e-10` Pearson
  guard, M0 gate; see `Ms1Calculators.cs:40-60`).
- `ScoreCandidate` collapses to: extract → run 21 calculators → assemble `FdrEntry`.
- Median-polish stays harness-published (diagnostics live in the exe layer
  `OspreySharp.Scoring` cannot reference); the crop+`WriteMpInputsRow`+`Compute`
  may move into the extractor with the dump call routed through the injected
  `IScoringDiagnostics`. Output-gated.

### Commit 3 — N=2 bounded apex accessor (least privilege on raw spectra)
- Replace the raw-window exposure on `IOspreyApexSpectraPeakData` (`WindowSpectra`,
  `WindowStartIndex`, `WindowLength`, `ApexLocalIndex`) with a single bounded accessor
  `bool TryGetApexOffsetSpectrum(int offset, out Spectrum s, out int cacheIndex)` for
  `offset ∈ [-2,+2]`, returning false at window edges. Folds the documented index trap
  (`IOspreyPeakData.cs:88-113`) and the asymmetric boundary skip
  (`XcorrCalculators.cs:147-148`) into the one accessor — byte-identically.
- Enforced at the INTERFACE; `OspreyPeakData` keeps its window reference internally
  (no per-candidate 5-element copy) so the bound is a contract boundary, not an
  allocation. The window-global `PreprocessedXcorr` cache stays on the context
  (per-window preprocessing is perf-critical), reached via the returned `cacheIndex`.
- N=2 is the Savitzky-Golay filter half-width (`XcorrCalculators.cs:105-112`); nothing
  reads wider. **Perf gate is the watch item** (hot path).

## Gates (per commit)
- **Correctness (byte-identical output)**: `regression.ps1 -Dataset Stellar`
  (`-Dataset All` before opening/finalizing the PR). Self-contained C# golden + resume
  leg at 1e-9; no Rust checkout. See [[feedback_ospreysharp_csharp_regression_gate]].
- **Build + tests + zero-warning inspection**:
  `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`.
- **Performance (commit 3 especially)**: `Test-PerfGate.ps1 -Dataset Stellar`
  (same-session A/B vs pinned `pwiz-perfbase`, 3-rep median).
- If any feature value moves: **bisect and fix; do NOT widen tolerance**
  ([[feedback_bit_parity_tolerance]]).
- Skyline conventions: no async/await, resource strings, `_camelCase`, CRLF, helpers
  after public methods, AI-attribution headers ([[feedback_ai_attribution]]).

## Out of scope (future)
- Shared `pwiz_tools\Shared` scoring assembly + Skyline referencing the contract
  (`TODO-ospreysharp_skyline_shared_scoring`). This commit only makes the C# side
  *closer* to portable; it does not move code into a shared DLL.
- Narrowing MS1 further than "produced upstream" (e.g. RT-windowed MS1 spectra list) —
  the producer-seam reframing supersedes the earlier "narrow the window list" idea.

## Progress log
### 2026-06-21 - Merged
PR #4320 squash-merged to master as `09269b4205`. Shipped the four-tier scoring
peak-data hierarchy (Summary/Detailed/ApexSpectrum/ApexSpectra) with all 21 PIN
calculators reclassified, the `PeakDataExtractor` producer seam, the MS1 production
lift (MS1 scores now Detailed-tier consumers), and the N=2 bounded apex accessor --
all byte-identical on Stellar+Astral with perf flat-to-faster. Also folded in a
`regression.ps1` self-clean of its TestResults scratch (per phase/dataset + on
failure, `KeepRunDirs=0` default, `-KeepOutput` opt-out) to fix the build-agent
out-of-disk failure (agent build #4054724); validated locally and the overnight
agent perf/regression runs passed. Review: self-review clean; Copilot + ultrareview
each found only doc nits, all addressed/resolved. No scope deferred.

- 2026-06-20: **Commit 1 done + pushed** (`bfffe32ec8`). Four-tier hierarchy +
  4 calculator bases; all 21 calculators reclassified (2 Summary / 10 Detailed /
  5 ApexSpectrum / 4 ApexSpectra). Behavior-free; Stellar+Astral byte-identical
  (golden/resume/HPC-chain), build + 389 tests + zero-warning inspection.
  **PR [#4320](https://github.com/ProteoWizard/pwiz/pull/4320)** opened as draft
  (TeamCity per push; Copilot deferred to final state).
- 2026-06-20: **Commit 2 done + pushed** (`dacf6ed7c6`). `PeakDataExtractor`
  producer seam (scan-range/XIC/peak-detect/apex resolution + all detection
  diagnostics); `ScoreCandidate` collapsed to extract→score→assemble. MS1 precursor
  XIC + isotope envelope produced upstream and exposed on the Detailed tier; the two
  MS1 scores became pure consumers (dropped to Detailed); removed the now-dead MS1
  machinery from `OspreyScoringContext`. Dropped dead `libCosine`/`top6Matches`.
  Byte-identical Stellar+Astral. **Perf gate PASS** (Stellar A/B vs perfbase:
  stage1to4 -3.7%, total -1.8% median — scoring slightly faster; `ExtractedPeak`
  alloc immaterial). Perf-gate data path note: pass `-TestBaseDir
  'D:\Users\brendanx\Downloads\Perftests\osprey-testfiles-mzML'` (its default
  `D:\test\osprey-runs\stellar` is unstaged on this machine).
- 2026-06-20: **Commit 3 done + pushed** (`7ba0a13c5f`). Replaced the four window
  members with the bounded `TryGetApexOffsetSpectrum(offset, out spectrum, out
  cacheIndex)` (apex±2, owns the index mapping + edge skip); SG sweep reaches spectra
  only through it. Dropped now-dead `WindowRetentionTimes`. **Stellar+Astral
  byte-identical** (golden/resume/HPC-chain); **perf gate PASS** (Stellar A/B
  stage1to4 -2.9%, total -1.3%).
- 2026-06-20: **Self-review (fresh-context agent) clean** — no CRITICAL/HIGH; verified
  MS1-lift fidelity, stale-state reset, accessor index math, tier classifications,
  concurrency. Addressed its one actionable LOW by adding a direct unit test of the
  production `OspreyPeakData.TryGetApexOffsetSpectrum` (`d1155f9e5b`, +1 test → 390).
- 2026-06-20: **All gates green across all 4 commits.** PR
  [#4320](https://github.com/ProteoWizard/pwiz/pull/4320) marked ready for Copilot.
  Remaining: `/pw-respond` Copilot, then complete on merge.
- 2026-06-20: Branch created off master `a0065b3efa`. Design settled with the
  developer: 4 tiers (Summary/Detailed/ApexSpectrum/ApexSpectra) — revising the
  modular-scoring "all Detailed" decision; MS1 reclassifies Detailed in commit 2 via
  upstream production; N=2 bounded accessor in commit 3. TODO opened; implementing
  commit 1.
