# TODO-20260819_osprey_gbt_regression.md

## Branch Information
- **Branch**: `Skyline/work/20260819_osprey_gbt_regression`
- **Base**: `master`
- **Created**: 2026-08-19
- **Status**: In Progress
- **GitHub Issue**: [#4592](https://github.com/ProteoWizard/pwiz/issues/4592)
- **PR**: (pending)

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

### Phase 4: Pre-review

- [ ] `/pw-self-review`
- [ ] TeamCity
- [ ] Human review

## Unrelated Build Fix Included

`Osprey.Scoring/PickLdaModel.cs` was missing `using System.Linq;` for its
`dto.Features.SequenceEqual(...)` call, so `Osprey.Scoring` did not compile on either
target framework. The break arrived with `dd9e84581` (the same commit that added the
GBDT). One line added here because nothing in Osprey builds or tests without it.

**Reviewer note**: happy to split this into its own PR if preferred.

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
- `pwiz_tools/Osprey/Osprey.Scoring/PickLdaModel.cs` (unrelated build fix, see above)

## Follow-up Work

- `Train` still takes `double[][] x`. At 9.1M rows x 22 features that is roughly 1.8 GB of
  jagged-array overhead before any bins are built. A column-major entry point would remove
  it, but it changes the public surface and belongs in its own change.
- Histogram subtraction is worth roughly a 2x training speedup and should be revisited if
  the bit-identity constraint is ever relaxed behind an opt-in flag.
