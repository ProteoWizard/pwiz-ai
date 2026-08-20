# TODO-20260819_osprey_gbt_regression.md

## Branch Information
- **Branch**: `Skyline/work/20260819_osprey_gbt_regression`
- **Base**: `master`
- **Created**: 2026-08-19
- **Status**: In Progress
- **GitHub Issue**: [#4592](https://github.com/ProteoWizard/pwiz/issues/4592)
- **Module**: `osprey`
- **PR**: [#4595](https://github.com/ProteoWizard/pwiz/pull/4595)

## Objective

Add a squared-error (regression) objective to `Osprey.ML.GradientBoostedTrees`, so the
same boosting implementation can serve both the Percolator-replacement FDR path (binary
logistic) and m/z calibration for MARS (regression), without a second copy of the
split-finding code drifting silently.

Hard requirement: **the logistic path must be bit-identical before and after.** Everything
except the base score and the per-round gradient is shared between the two objectives, so
any change made for regression lands directly under FDR scoring.

## Context

MARS (Mass Accuracy Recalibration System) is being ported from Python to C#. Its
calibration model is an XGBoost `reg:squarederror` regressor over ~22 spectral features.
`GradientBoostedTrees` already implements the same regularized objective for logistic
loss: quantile binning, histogram split finding, Newton boosting, L1 + L2 leaf penalties,
gamma, min_child_weight, subsampling, and deterministic-by-construction training.

Adding the objective upstream keeps `Osprey.ML` the sole owner of the model. The
alternative -- forking the file into the MARS repository -- would let the split-finding
code diverge between the two consumers with nothing to catch it.

Two scale facts drove the performance part of this change. `Osprey.FDR` trains on roughly
100k rows; MARS trains on 350k rows for a Stellar run and **9.1M rows x 22 features** for
an Astral plate. At that size the original storage and allocation strategy is the
bottleneck, not the arithmetic.

## Implementation Plan

### Phase 1: Objective switch

- [x] Add `GbtObjective` enum (`LogisticBinary`, `SquaredError`)
- [x] Add `GbtParams.Objective`, defaulting to `LogisticBinary`
- [x] Base score branches: weighted mean of y for squared error, existing log-odds otherwise
- [x] Per-round gradient branches: `g = (f - y) * w`, `h = w` for squared error
- [x] Add `Train(double[][] x, double[] y, GbtParams p, double[] sampleWeight = null)` overload
- [x] Keep `Train(double[][] x, bool[] isDecoy, ...)` as a thin wrapper that builds y

### Phase 2: Bit-identical performance work

All four preserve summation order exactly, which is why the logistic golden still matches.

- [x] Bin matrix flattened to a single column-major `byte[]` (was `byte[n][nFeat]`, i.e.
      one small array per row -- 9.1M object headers at Astral scale)
- [x] Histogram buffers pooled one per depth level (was a fresh `double[maxBins]` pair per
      feature per node)
- [x] In-place stable row partitioning over a single index permutation (was a `List<int>`
      pair plus `ToArray()` at every node)
- [x] Optional histogram parallelism ACROSS FEATURES only, via
      `GbtParams.MaxDegreeOfParallelism`, **defaulting to 1** so the FDR path stays exactly
      sequential. One thread owns a feature and walks the node's rows in ascending order,
      so the model is bit-identical at any thread count.

Deliberately NOT done: histogram subtraction (deriving a sibling's histogram from parent
minus smaller child). It would roughly halve the work per level but changes the floating
point result, so it cannot coexist with the bit-identity requirement.

### Phase 3: Tests

- [x] `MLTest.TestGbtSquaredErrorObjective`, consolidating three validations:
  - `AssertLogisticGoldenUnchanged` -- ten exact golden scores captured from the
    implementation at `dd9e84581`, asserted with exact equality rather than a tolerance
  - `AssertRegressionFitsContinuousTarget` -- squared error must fall below 5% of the
    weighted-mean baseline the model starts from
  - `AssertRegressionThreadInvariant` -- identical scores at 1 and 4 histogram threads
- [x] Full `Osprey.Test` suite green on net472 and net8.0 (587/587 both)

### Phase 4: Model persistence

Added in a second commit, because MARS needs `mars apply --model` and Osprey holds GBT
models in memory only. `FrozenModelScorer` looks like it wants this too.

- [x] `GbtModelData`, a plain-array snapshot, plus `ToModelData` / `FromModelData`
- [x] `FromModelData` validates the node graph rather than trusting it, so a truncated or
      hand-edited model file fails at load instead of scoring silently wrong
- [x] Snapshots are copies, so mutating one cannot reach back into the model
- [x] `MLTest.TestGbtModelDataRoundTrip` covers the exact score round-trip and each
      rejection path
- [x] Logistic golden still bit-identical after the addition

### Phase 5: Copilot review feedback (PR #4595)

All four findings were valid. Fixed in `00d11d7`.

- [x] The binary-label `Train` overload rejects a `GbtParams` whose `Objective` is not
      `LogisticBinary`. It promises a log-odds margin that callers rank by, and a params
      instance carried over from a regression call would have fitted squared error to 0/1
      labels and returned something q-value and PEP estimation cannot consume. The
      scenario is one this PR itself creates: before it there was no reason to have a
      non-logistic `GbtParams` in existence.
- [x] Null checks for `x` and `p`, and a length check for `sampleWeight`, on both
      overloads. These would have surfaced as an NRE or an index-out-of-range partway
      through boosting, pointing at boosting internals rather than at the bad argument.
- [x] `FromModelData` rejects cycles. Range checks alone let `Left[i] = i` through, and
      `ScoreSingle` would then spin forever rather than fail. The invariant is safe to
      enforce because `BuildTree` appends a node before recursing into its children, so a
      child index always exceeds its parent's and the two differ. Leaves must also carry
      `-1` in both child slots.
- [x] `MLTest.TestGbtTrainArgumentValidation` covers every rejection path plus the case
      that must still succeed; `TestGbtModelDataRoundTrip` gains the cycle and stale-leaf
      cases.

Bit-identity re-verified afterwards, since that is the guarantee the PR turns on: all
1,925 golden logistic scores still hash to `242558FF...`, identical at 1, 4 and 16
threads, and the regression fixture's 90 output lines are unchanged as well. Every fix is
validation that runs before training starts, so this is the expected result rather than a
lucky one.

`Osprey.Test`: 589/589 on net8.0 and net472, 0 warnings.

### Phase 6: Code review feedback

`/code-review` run over both branches. PR #4594 (since withdrawn): no findings. PR #4595:
fifteen findings, twelve fixed in `4c83c8a`, one split out, two partially pushed back on.

- [x] `GbtModelData` records `FeatureCount` and `Objective`; both validated on load, and
      `ScoreSingle` rejects a short feature vector. Without them a corrupted split feature
      threw inside `ScoreSingle` (the exact failure the doc claimed to prevent), and a
      reloaded regression margin was indistinguishable from a log-odds.
- [x] The continuous-target overload validates the target against the objective and
      rejects an unknown objective, closing the reverse of the hole fixed last round.
- [x] Sample weights must be finite and non-negative. A negative weight could cancel
      `RegLambda` exactly and put a NaN leaf into every later round; `RegLambda` is
      settable to 0 through `OSPREY_GBT_LAMBDA`, so it was reachable.
- [x] Fixed a vacuous snapshot-isolation assertion that compared two values both
      recomputed after the mutation, so it passed even with the clones removed.
- [x] The golden logistic assertion now also runs at 4 threads. Thread invariance had only
      ever been asserted under squared error, which is not the path the guarantee protects.
- [x] The golden test owns its parameters instead of sharing `FastGbt()`.
- [x] Allocation and sizing work in the parallel path; `MaxBins` clamp documented.
- [x] `docs/16-determinism.md` Step 7 records the one parallel float accumulation, its
      across-features invariant, and the two changes that would silently break the 1e-9
      parity gate.

**Split out**: NaN routes left when binning and right when walking the tree, so rows with
missing values shape a leaf they can never reach. Real and pre-existing, but fixing it
changes trained models for NaN-containing input and would break this PR's bit-identity
premise. Filed as [#4596](https://github.com/ProteoWizard/pwiz/issues/4596).

**Pushed back**: the recommendation to call `OspreyParallel.For` instead of `Parallel.For`
is right about ThreadPool contention but wrong about the mechanism - `OspreyParallel`
allocates dedicated Threads per call, fine at fold granularity but ruinous at ~63 nodes x
200 trees. Hoisted the options and delegate, gated dispatch on total work, and documented
the caveat at the call site instead.

Verification after the fixes: golden logistic still `242558FF...` at 1, 4 and 16 threads,
regression fixture unchanged, `Osprey.Test` 589/589 on net8.0 and net472.

MARS knock-on: the vendored copy was re-synced and `MarsModelIo` now writes and reads the
two new fields, deriving them for files written before they existed. MARS 60/60 green.

### Phase 7: Pre-merge

- [ ] TeamCity
- [ ] Human review

## Status

Both commits are on the branch locally and NOT pushed. Osprey.Test is green on both
target frameworks: 588/588 on net472 and 588/588 on net8.0.

The consumer is the MARS .NET port in the `mars` repository, which vendors these files
with a SHA-256 drift guard and has been validated end to end against the Python
implementation on a five-file Stellar cohort:

| Metric | Python | C# |
|---|---|---|
| Fragments matched | 352,349 | 352,349 |
| Pre-correction std | 0.1180 Th | 0.1180 Th |
| Post-correction MAD | 0.0435 Th | 0.0449 Th |
| Post-correction RMS | 0.0858 Th | 0.0854 Th |

## Build environment

This work started on the .NET 9 SDK, where nothing in Osprey compiled:
`Osprey.Scoring/PickLdaModel.cs` calls `dto.Features.SequenceEqual(ExpectedFeatures)` on
`string[]` with only `using System;` imported. That binds to
`System.MemoryExtensions.SequenceEqual` through the C# 14 first-class-spans conversion in
extension receiver position; under C# 13 the only candidate is
`System.Linq.Enumerable.SequenceEqual`, which the file does not import, so it fails with
CS1061.

Master is not broken. Osprey requires the .NET 10 SDK (VS 2026), which is what TeamCity
and the Skyline developers build with. The fix was to upgrade this machine, done: SDK
10.0.400. Everything below was re-verified on it.

A branch and PR that pinned `<LangVersion>14</LangVersion>` to make that requirement
explicit was withdrawn as unnecessary given the stated toolchain requirement. This branch
was rebased off it and targets `master` directly. See
`ai/todos/completed/TODO-20260820_osprey_scoring_linq_build_fix.md`.

## Verification

Bit-identity was established with an out-of-tree harness that compiles the real
`GradientBoostedTrees.cs` (linked, not copied) against a verbatim `XorShift64` shim,
trains the logistic path over five fixtures -- default params, fast params, depth-6 with
256 bins, a heavily regularized configuration with L1 and subsampling, and a degenerate
case carrying NaN, positive and negative infinity, and two constant columns -- and prints
all 1925 resulting scores at round-trip precision.

- Pre-change output: SHA256 `242558FF0A6FCD3A5C34BE0A57BD42848A706853BD51E998E21C7B8856852A22`
- Post-change output: identical, byte for byte
- Post-change at 1, 4, and 16 histogram threads: identical to each other

The ten golden values embedded in `MLTest` were generated from the `origin/master` file
content and independently reproduced by the modified file.

## Files Modified

- `pwiz_tools/Osprey/Osprey.ML/GradientBoostedTrees.cs`
- `pwiz_tools/Osprey/Osprey.Test/MLTest.cs`

## Follow-up Work

- `Train` still takes `double[][] x`. At 9.1M rows x 22 features that is roughly 1.8 GB of
  jagged-array overhead before any bins are built. A column-major entry point would remove
  it, but it changes the public surface and belongs in its own change.
- Histogram subtraction is worth roughly a 2x training speedup and should be revisited if
  the bit-identity constraint is ever relaxed behind an opt-in flag.
