# TODO-20260421_osprey_gauss_solver.md — Gauss-Jordan solver robustness (both tools)

## Branch Information

- **pwiz branch**: `Skyline/work/20260421_osprey_gauss_solver`
  (to be created off `master` post-#4155-merge — that merge already
  landed as commit `f1db9f635` on 2026-04-21)
- **Base**: `master`
- **Working directory**: `C:\proj\pwiz\pwiz_tools\OspreySharp\`
- **Created**: 2026-04-21
- **Status**: Planning (Rust branch scaffolded; OspreySharp branch
  pending)
- **GitHub Issue**: (none — addresses Copilot review threads on
  [ProteoWizard/pwiz#4155](https://github.com/ProteoWizard/pwiz/pull/4155))
- **PR (pwiz)**: (pending)
- **PR (maccoss/osprey)**: (pending — local branch
  `gauss-abs-pivot-tolerance` already scaffolded on
  `C:\proj\osprey`)

## Objective

Address three deferred Copilot findings from pwiz PR #4155 that are
parity-affecting and therefore require coordinated PRs in both
tools:

1. **GaussSolver partial pivoting uses signed value, not absolute**
   ([Copilot comment](https://github.com/ProteoWizard/pwiz/pull/4155#discussion_r3111986866))
   — pivot row selection picks the row with the largest *signed*
   value in the current column. Negative pivots with large
   magnitude are skipped in favor of small-magnitude positives,
   hurting numerical stability. Fix: select the row with the
   largest `.abs()`.

2. **GaussSolver zero-pivot guard uses exact equality**
   (same Copilot thread) — `if self.left[(i, k)] == 0.0` on a
   floating-point value that has been through elimination is
   fragile. Fix: use `abs() < eps` tolerance.

3. **`LeftSolved()` uses exact float comparisons and only checks
   positive off-diagonals**
   ([Copilot comment](https://github.com/ProteoWizard/pwiz/pull/4155#discussion_r3111986886))
   — the post-solve identity check uses `x != 1.0 && x != 0.0` on
   diagonals (fails to accept values that are "approximately 1 or
   0" after elimination) and `x > 1E-8` on off-diagonals (accepts
   arbitrarily negative residuals). Fix: tolerance-based
   `(x - 1).abs() < tol` on diagonals and `x.abs() < tol` on
   off-diagonals.

Also in scope:

4. **Unit tests for negative-pivot and near-singular cases**
   ([Copilot comment](https://github.com/ProteoWizard/pwiz/pull/4155#discussion_r3111987020))
   — add regression tests to both Rust (`gauss.rs` tests module)
   and OspreySharp (`MLTest.cs` or new `GaussTest.cs`) that cover
   (a) matrices requiring abs-value pivot selection, (b)
   near-singular inputs that should return `None`/`null`.

## Why parity-affecting

`Gauss::solve` is called by `LinearDiscriminantAnalysis::fit` in
both tools to solve `scatter_within * x = scatter_between` during
LDA training. Changing pivot row selection OR zero-pivot tolerance
changes which rows get swapped and which get zeroed at each step
of Gauss-Jordan elimination. That changes the numerical result of
the solve (bit-level), which propagates through the LDA
eigenvector, then through main-search scoring. We verified
empirically on pwiz PR #4155 (Session 20 in
`TODO-20260409_osprey_sharp.md`) that porting the abs-pivot change
to only OspreySharp broke Stellar parity immediately.

`LeftSolved` is the post-solve acceptance predicate. Changing its
tolerance changes accept/reject decisions for borderline solves.
For matrices that currently pass the exact check (identity or
all-zero rows), relaxing to a tolerance has no effect. For
matrices that currently fail but pass tolerance-based checks,
`Gauss::solve` will now return `Some` instead of `None`, which
changes LDA output from `None` to a scored vector. This also
risks parity until both tools agree.

## Strategy

### Step 1: Coordinated branch setup

Already partially done:

- Rust: `C:\proj\osprey` branch `gauss-abs-pivot-tolerance` exists
  (created off `main` at `bd15572`, no commits yet — the
  `linear_discriminant.rs` diff was dropped in favor of PR
  [maccoss/osprey#14](https://github.com/maccoss/osprey/pull/14)
  which handles LDA single-class guard separately).
- OspreySharp: create `Skyline/work/20260421_osprey_gauss_solver`
  off `C:\proj\pwiz` master (includes the merged
  `pwiz_tools/OspreySharp/` from #4155).

### Step 2: Implement fixes in both tools simultaneously

Rust `crates/osprey-ml/src/gauss.rs`:

```rust
// In echelon() — change pivot selection and zero-guard
let mut max = (0, 0.0f64);
for i in h..m {
    let abs_val = self.left[(i, k)].abs();
    if abs_val > max.1 {
        max = (i, abs_val);
    }
}
let i = max.0;
const EPS: f64 = 1E-12;
if max.1 < EPS {
    k += 1;
    continue;
}

// In left_solved() — change tolerances
const TOL: f64 = 1E-8;
if i == j {
    if (x - 1.0).abs() > TOL && x.abs() > TOL {
        return false;
    }
} else if x.abs() > TOL {
    return false;
}
```

OspreySharp `pwiz_tools/OspreySharp/OspreySharp.ML/GaussSolver.cs`:
identical logic — use `Math.Abs(...)` in `Echelon` pivot selection
and zero-guard, use `Math.Abs(x - 1.0) < tol` and
`Math.Abs(x) < tol` in `LeftSolved`. Requires
`using System;` import (not currently present; added + reverted
during Session 20's failed first attempt — re-add with the fix).

### Step 3: Verify parity of the coordinated change

Build both tools with the fix applied locally (not yet pushed to
either repo). Run `Test-Features.ps1 -Dataset Stellar` and
`-Dataset Astral`. Expect 21/21 at 1e-6 on both datasets because
the fix is applied symmetrically. If parity breaks, the fix has a
subtle implementation difference between the two tools — debug
before proceeding.

### Step 4: Unit tests

Rust `crates/osprey-ml/src/gauss.rs` tests module: add tests for
negative-pivot case (e.g. a 3x3 where the correct pivot row has
the largest-magnitude negative entry) and near-singular case
(e.g. a rank-deficient matrix where solve should return `None`).

OspreySharp `pwiz_tools/OspreySharp/OspreySharp.Test/MLTest.cs`:
mirror the same two test cases. Use the same matrices so drift
between the two test suites is easy to spot.

### Step 5: Upstream PRs in coordinated order

Option A: Land Rust first, then port to OspreySharp.

1. Commit and push `gauss-abs-pivot-tolerance` branch to
   `maccoss/osprey`, open PR with reference to Copilot comments on
   ProteoWizard/pwiz#4155.
2. After Mike merges, rebuild `C:\proj\osprey` at the new `main`.
3. Apply matching OspreySharp changes + tests on
   `Skyline/work/20260421_osprey_gauss_solver`.
4. Verify Stellar + Astral 21/21 against the new Rust.
5. Open pwiz PR referencing the merged Rust PR.

Option B: Land both PRs simultaneously with cross-references.

1. Open both PRs at the same time, each referencing the other in
   its description.
2. Merge Rust first, then immediately rebuild OspreySharp against
   new Rust and merge pwiz side.

Option A is safer (one change at a time) but takes longer. Option
B requires coordination with Mike's review cadence. Default to
**A** unless Mike prefers B.

### Step 6: Respond to Copilot threads on #4155

Three threads on pwiz #4155 are already resolved with "deferred"
explanations pointing at this TODO. Once the pwiz-side gauss
solver PR merges, follow up on those threads with the merged PR
link.

## Tasks

### Priority 1: Rust implementation

- [ ] Rust: apply abs-pivot fix in `echelon()` on
      `gauss-abs-pivot-tolerance` branch
- [ ] Rust: apply tolerance fix in `left_solved()`
- [ ] Rust: add two regression tests (negative-pivot,
      near-singular)
- [ ] Rust: `cargo fmt` + `cargo clippy` + `cargo test --workspace`
      clean
- [ ] Rust: commit, push to `maccoss/osprey`,
      `gh pr create` referencing Copilot threads
      [r3111986866](https://github.com/ProteoWizard/pwiz/pull/4155#discussion_r3111986866)
      and [r3111986886](https://github.com/ProteoWizard/pwiz/pull/4155#discussion_r3111986886)

### Priority 2: OspreySharp implementation

- [ ] Rebuild `C:\proj\osprey` at `main` after Rust PR merges
- [ ] Create pwiz branch off master:
      `Skyline/work/20260421_osprey_gauss_solver`
- [ ] Apply matching abs-pivot + tolerance fixes in
      `GaussSolver.cs` (re-adding `using System;`)
- [ ] Add parallel regression tests in `MLTest.cs`
- [ ] Verify `Test-Features.ps1 -Dataset Stellar` 21/21 at 1e-6
- [ ] Verify `Test-Features.ps1 -Dataset Astral` 21/21 at 1e-6
- [ ] `Build-OspreySharp.ps1 -RunInspection -RunTests` clean
- [ ] Commit, push, open pwiz PR referencing the merged Rust PR

### Priority 3: Review thread followup

- [ ] Reply to [r3111986866](https://github.com/ProteoWizard/pwiz/pull/4155#discussion_r3111986866)
      with the merged pwiz PR link
- [ ] Reply to [r3111986886](https://github.com/ProteoWizard/pwiz/pull/4155#discussion_r3111986886)
      with same
- [ ] Reply to [r3111987020](https://github.com/ProteoWizard/pwiz/pull/4155#discussion_r3111987020)
      noting regression tests landed with the fix

## Critical reminders

1. **Parity-affecting change — land symmetrically.** The whole
   reason this PR was deferred from #4155 is that changing one
   tool without the other produced bit-level divergence on
   Stellar. Do not commit the OspreySharp side until the matching
   Rust fix is in `C:\proj\osprey:main`.
2. **Existing Stage 1-4 parity is the gate.** Re-run
   `Test-Features.ps1` on both datasets after any change. 21/21
   at 1e-6 is non-negotiable.
3. **The tests should fail without the fix.** A regression test
   that passes against the old buggy code proves nothing. Before
   committing the fix, verify each test would fail with the
   pre-fix implementation (temporary revert + run, then re-apply
   fix).
4. **Both tools' tests should use the same input matrices.** If
   Rust and C# regression tests use different numerical inputs,
   future drift is easy to miss. Port the exact same matrices.

## Progress Log

(Starts on first session against this TODO.)
