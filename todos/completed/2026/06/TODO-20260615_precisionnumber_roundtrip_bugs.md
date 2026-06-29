# TODO-20260615_precisionnumber_roundtrip_bugs.md

## Branch Information
- **Branch**: `Skyline/work/20251225_SpectrumFilterParser` (PR #4115)
- **Owner**: Nick (precision-filtering subsystem)
- **Related**: [[TODO-20260219_precision_filtering]] — same work, merged into this branch.
- **Status**: **COMPLETED — merged in PR #4115 (2026-06-24).** Root cause was a CI gap (TeamCity bt209 never ran `CommonTest.dll`, hiding two long-red tests); the gap was fixed separately and all three fixes shipped. Nick reviewed and merged, settling the two "your call on the layer" design notes below as accepted-as-implemented.

## Summary

Two CommonTest tests were red on the branch (and had been since ~2026-03-29):
- `CommonTest.DataBinding.FilterSpecTest.TestFilterSpecRoundTrips`
- `CommonTest.PrecisionNumberTest.TestFinitePrecisionNumbers`

They were invisible because **TeamCity wasn't running `CommonTest.dll`** (bt209's test
step ran `Test.dll,TestData.dll` + named functional tests, never CommonTest). That CI
gap is now fixed separately, so these must go green. They fail in every culture (not a
localization-only issue). All three fixes below are in; the **entire `CommonTest`
assembly now passes** (32s), `TestCollisionEnergyFilter` still passes, and CodeInspection
is clean.

## The fixes

### #2 — `PrecisionNumber.cs` (TestFinitePrecisionNumbers): full-precision drops a digit for sub-1 magnitudes
- `TryParse` routed the "full precision, no exponent" case through `CountDecimalPlaces`,
  which returned `MAX_SIGNIFICANT_DIGITS` (17) as a **decimal-places** count;
  `WithDecimalPlaces(value, 17)` then computed `significantDigits = 17 + magnitude + 1`,
  yielding **16** for magnitude −2. So a MAX-precision `0.0314159265358979` round-tripped
  to 16 sig digits and re-printed in scientific notation.
- **Fix:** intercept that case in `TryParse` and build via significant digits directly:
  ```csharp
  if (defaultToFullPrecision && text.IndexOfAny(new[] { 'e', 'E' }) < 0)
  {
      result = WithSignificantDigits(value, MAX_SIGNIFICANT_DIGITS);
      return true;
  }
  ```
  Removed the now-dead `else if (defaultToFullPrecision) return MAX_SIGNIFICANT_DIGITS;`
  branch and the unused `defaultToFullPrecision` parameter from `CountDecimalPlaces`.

### #1b — `PrecisionNumber.cs`: cannot parse its own serialized scientific form
- `NumericFilterHandler` serializes sub-MAX-precision values in scientific form (e.g. `1.5`
  → `"1.5E+0"`, intentional: the exponent encodes a sig-digit count below MAX). But
  `decimal.TryParse` rejects exponent notation, and `TryParse`'s `double` fallback only
  handled `NaN`/`Infinity` — finite values fell through to `return false`. So
  `DeserializeOperand` (invariant) **threw `FormatException` on any serialized sub-MAX
  operand** — a real round-trip bug, not just a test artifact.
- **Fix:** in the `double` fallback, accept finite values too:
  ```csharp
  // decimal.TryParse rejects exponent notation, but PrecisionNumber serializes sub-MAX
  // precision values in scientific form (e.g. "1.5E+0"); fall back to the finite
  // double-parsed value so a serialized operand can always be read back.
  value = (decimal) doubleValue;
  ```
- NOTE for Nick: an alternative is to make `ToString` emit a decimal form `decimal` can read,
  but the scientific form is deliberate (encodes sig digits), so hardening `Parse` is the
  lower-risk fix. Your call on the preferred layer.

### #1a + test-locale — `FilterSpecTest.cs` (TestFilterSpecRoundTrips)
Two issues in the test:
- **Integer operands normalize to `double`.** `int` columns use `IntegerFilterHandler`
  (`FilterHandler<double,double>`), so the operand comes back as `double` by design. The
  test asserted exact CLR-type fidelity (`int 0` vs `double 0`). This is the handling you
  *removed* in `cd36b466a` (the `predicateOperandValue is double ? Convert.ChangeType…`
  block); `IntegerFilterHandler` (`42670b5aa`, 3/29) then reintroduced the double, so the
  removal is what regressed it. **Fix:** restored that double-conversion in the comparison.
- **`CallWithCulture` was a no-op.** The test re-parsed the invariant operand text inside
  `LocalizationHelper.CallWithCulture(CultureInfo.InvariantCulture, …)`, expecting that to
  drive the parse locale. But `FilterPredicate.Parse` takes its locale from
  `dataSchema.DataSchemaLocalizer.FormatProvider` (the schema's culture = fr-FR/tr-TR),
  ignoring the thread culture — so the invariant `"1.5E+0"` was parsed under a comma-decimal
  culture and failed. **Fix:** re-parse with an **invariant-localized** `DataSchema` instead
  of the wrapper.

## Verification
- `Run-Tests CommonTest.dll` → all pass (32s).
- `TestCollisionEnergyFilter`, `CodeInspection` → pass (no regression from the
  `PrecisionNumber` change).

## Files changed
- `pwiz_tools/Shared/CommonUtil/SystemUtil/PrecisionNumber.cs` (#2, #1b)
- `pwiz_tools/Skyline/CommonTest/DataBinding/FilterSpecTest.cs` (#1a + test-locale)

## Open design question for Nick
Should `InvariantOperandText` be re-parseable across cultures (as `SpectrumClassFilter.ParseFilterString`
already supports via multi-culture attempts)? The test now reads invariant text with an
invariant schema, which is correct for storage round-trips; if cross-culture leniency is
also wanted at the `FilterPredicate.Parse` layer, that's a separate enhancement.
