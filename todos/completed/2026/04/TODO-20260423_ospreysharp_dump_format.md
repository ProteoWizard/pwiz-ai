# TODO-20260423_ospreysharp_dump_format.md — Stage 5+ dump text parity

> Sibling of **TODO-20260423_osprey_sharp_stage6.md**. Pre-requisite
> tidy-up before the Stage 6 walk: align OspreySharp's Stage 5 dump
> text format with Rust's so diagnostic files are byte-identical
> (SHA-256 equal) across the two tools, not just numerically equal.

## Branch Information

- **pwiz branch**: `Skyline/work/20260423_ospreysharp_dump_format`
- **osprey branch**: none (Rust already uses shortest-roundtrip via `format_f64_roundtrip`)
- **Base**: `master`
- **Created**: 2026-04-23
- **Status**: Completed
- **GitHub Issue**: (none — tool work, no Skyline integration yet)
- **PR (pwiz)**: [#4163](https://github.com/ProteoWizard/pwiz/pull/4163) (merged 2026-04-23 at `80f5341bc`)

## Problem found 2026-04-23

The Stage 5 sub-sprint's "bit-parity on single-file Stellar"
(`Compare-Percolator.ps1` 1e-9 tolerance on 6 numeric columns) was
achieved via **numeric** comparison. Running an independent
SHA-256 byte-parity check across all three Stellar files on the
four Stage 5 dumps exposed that OspreySharp emits floats with
C#'s `.ToString("G17", inv)` — always 17 significant digits — while
Rust emits `format!("{}", v)` which is ryu's *shortest* decimal that
roundtrips. Same f64, different text:

    Rust:       5.598374948209159
    OspreySharp: 5.5983749482091589

Both parse back to the same bits; neither is wrong. But as text
they diverge, so byte-parity via `Get-FileHash` fails on three of
the four dumps (standardizer / svm_weights / percolator). The
subsample dump passes because it only serialises integers +
booleans.

Yesterday's Copilot follow-up (`ef209ea` / pwiz #4160) reconciled
the class-level OspreyDiagnostics XML doc to call out "Stage 5 uses
G17 to match Rust's G17 choice" — that line was wrong. Rust does
not use G17; it uses ryu-shortest. The doc gets corrected as part
of this change.

## Fix

1. New helper `pwiz.OspreySharp.Core.Diagnostics.FormatF64Roundtrip(double)`
   in `OspreySharp.Core/Diagnostics.cs`. Mirrors Rust's
   `format_f64_roundtrip`:
   - `NaN` -> `"NaN"`; `+inf` -> `"inf"`; `-inf` -> `"-inf"`;
     both `+0` and `-0` -> `"0"` (normalizes signed zero).
   - Otherwise: use `.ToString("R", inv)` and verify the result
     round-trips via `double.Parse`. On .NET Core 3+ / .NET 5+ "R"
     is the shortest decimal that parses back to the same bits --
     matches Rust's ryu exactly. On .NET Framework 4.7.2 "R" has a
     long-standing bug where a minority of values produce
     non-round-tripping output; detect that via the parse-check
     and fall back to `G17` (always round-trips by IEEE 754
     guarantee, but may be one digit longer than ryu-shortest).
     Either way, expand any scientific-form result to fixed
     decimal since Rust's f64 Display never emits `e` notation.
   - Net472 diagnostic dumps will therefore agree with Rust on
     most values but be slightly more verbose for a minority.
     Compare-Stage5-AllFiles.ps1 defaults to net8.0 so the
     parity harness stays byte-identical.
2. Replaced 10 `.ToString("G17", inv)` call sites in the three
   Stage 5 dump writers:
   - `OspreySharp/OspreyDiagnostics.cs` -- Percolator dump
     (6 numeric columns).
   - `OspreySharp.FDR/PercolatorFdr.cs` -- SVM weights dump
     (2 sites: weight and bias) and standardizer dump (2 sites:
     mean and std).
3. Fixed the class-level XML doc on `OspreyDiagnostics` so future
   contributors see the correct story: Stages 1-4 use F10;
   Stages 5+ use `Core.Diagnostics.FormatF64Roundtrip`, not G17.
4. Added `DiagnosticsTest.cs` with four focused tests:
   - Special values (NaN, inf, ±0, trivial decimals).
   - Shortest-roundtrip on the real Stellar standardizer value
     `5.598374948209159` (Rust's ryu output).
   - Integer-valued f64 render without a trailing decimal (ryu
     compat: `100.0 -> "100"`).
   - Near-boundary values round-trip exactly (0.1/0.2/0.3 repeats,
     the 1e-4 scientific-form boundary, and a pair of standardizer
     values copied from the real Stellar dump).

## Gate for PR

- `Build-OspreySharp.ps1 -RunInspection -RunTests` green (done: 0
  warnings, 220/220 tests).
- `Compare-Stage5-AllFiles.ps1 -Dataset Stellar` reports `3/3 files
  byte-identical` across all four dumps.
- `Compare-Stage5-AllFiles.ps1 -Dataset Astral` reports `3/3`
  (after Astral generation runs -- tracked separately under the
  umbrella Stage 6 TODO).

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp_stage6.md` — Stage 6
  sub-sprint. Depends on this byte-identical dump text so its
  Stage 6 consensus / reconciliation / refined-FDR dumps can be
  compared via SHA-256 from the outset rather than with numeric
  tolerance.
- `ai/todos/completed/TODO-20260422_ospreysharp_stage5_diagnostics.md`
  — origin of the four Stage 5 dumps and the misattributed
  "G17 matches Rust G17" doc line.
- `C:\proj\osprey\crates\osprey-core\src\diagnostics.rs` — Rust
  reference implementation the helper mirrors.

## Progress log

### Session 1 (2026-04-23) — Built + net472 bug discovered

**Initial approach** (precision search `G1`..`G17` skipping scientific,
first one that round-trips): correct on .NET 8.0 but failed on
.NET Framework 4.7.2 for ~5 % of values. Root cause: net472's
`Double.ToString("G<p>")` at `p < 17` is not shortest-roundtrip-
correct -- for the real Stellar peak_sharpness std at bits
`0x41583D9959B55C3F`, net472's G16 returns `"6354533.401694357"`
(wrong last digit, fails parse-check), so the algorithm fell
through to G17 and emitted 17 digits vs. Rust's 16. Same
underlying issue as .NET Framework's long-known "R" bug.

**Final approach** (this file): use `"R"` + parse-check, fall
back to `G17`, then expand scientific to fixed decimal. Gives
byte-identical text with Rust on .NET 8.0 and valid-but-
potentially-longer text on .NET Framework 4.7.2. Unit tests
guard the all-framework round-trip; byte-match assertions are
wrapped in `#if NETCOREAPP || NET5_0_OR_GREATER`.

**Script defaults** for Compare-Stage5-AllFiles.ps1 and
Generate-AllScoresParquet.ps1 moved to `net8.0` so the harness
always runs on the framework with correct shortest-roundtrip.

- Added helper + tests + fixed 10 call sites + fixed class doc.
- Build/inspection/tests green on `net472` + `net8.0`.
- Stellar Stage 5 parity rerun: 3/3 byte-identical on all four
  dumps (std / sub / svm / perc) after switching harness default
  to net8.0 where ToString("R") is shortest-roundtrip-correct.

### Session 2 (2026-04-23) — Merged

PR [ProteoWizard/pwiz#4163](https://github.com/ProteoWizard/pwiz/pull/4163)
merged `2026-04-23T22:27:42Z` at squash commit `80f5341bc`.

Astral multi-file validation exposed a *separate* Stage-5-algorithm
divergence (Rust streaming vs C# direct) which is tracked in
`TODO-20260423_osprey_sharp_stage6.md` under the Percolator
streaming-path port task -- **not** a defect of this text-format
fix.
