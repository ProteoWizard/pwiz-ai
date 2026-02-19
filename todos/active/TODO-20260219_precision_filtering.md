# TODO-20260219_precision_filtering.md

## Branch Information
- **Branch**: `Skyline/work/20260219_PrecisionFiltering`
- **Base**: `master`
- **Created**: 2026-02-19
- **Status**: In Progress
- **GitHub Issue**: [#4019](https://github.com/ProteoWizard/pwiz/issues/4019)
- **PR**: (pending)

## Objective

Implement precision-aware numeric filtering in the Document Grid so that filter comparisons like "equals 3.14" match values that round to 3.14 at the detected precision level.

## Progress

### Completed
- [x] Created `PrecisionNumber` struct in `pwiz_tools/Shared/CommonUtil/SystemUtil/PrecisionNumber.cs`
  - Parses numbers detecting decimal precision
  - Supports regular numbers, scientific notation, negative numbers, locale fallback
  - `EqualsWithinPrecision(double)` for tolerance-aware equality
  - IEquatable, IComparable, operators
- [x] Updated `CommonUtil.csproj` with new file
- [x] Modified `FilterPredicate.MakePredicate` to wrap double operands as PrecisionNumber
- [x] Modified `FilterOperation.cs`:
  - OpEquals: precision-aware equality
  - OpNotEquals: precision-aware inequality
  - ComparisonFilterOperation: added virtual PrecisionComparisonMatches
  - OpIsGreaterThan: `value >= operand.Value + operand.Tolerance`
  - OpIsGreaterThanOrEqual: `value >= operand.Value - operand.Tolerance`
  - OpIsLessThan: `value < operand.Value - operand.Tolerance`
  - OpIsLessThanOrEqualTo: `value < operand.Value + operand.Tolerance`
- [x] Created `PrecisionNumberTest.cs` with parsing and precision matching tests
- [x] Extended `FilterOperationTest.cs` with `TestPrecisionFilterOperations`
- [x] Updated `CommonTest.csproj` with new test file
- [x] Build succeeds

### Remaining
- [ ] Fix boundary test case in `TestEqualsWithinPrecision` (line 96: `3.145` is exactly on the boundary and fails due to floating-point representation — `3.145` as a double is `3.14499...`, making `Math.Abs(3.14499... - 3.14) < 0.005` true)
- [ ] Run all tests green
- [ ] Run CodeInspection
- [ ] Create PR

## Key Design Decisions

1. **Tolerance = half unit in last place**: `0.5 * Math.Pow(10, -DecimalPlaces)`. This means "3.14" matches values in [3.135, 3.145).
2. **PrecisionNumber injected at MakePredicate level**: The operand is converted from double to PrecisionNumber before the predicate lambda is created, so each FilterOperation checks `operandValue is PrecisionNumber`.
3. **Comparison operators use virtual override**: `PrecisionComparisonMatches(double, PrecisionNumber)` is overridden in each comparison subclass.

## Known Issue

The `EqualsWithinPrecision` uses strict `<` for the tolerance check (`Math.Abs(value - Value) < Tolerance`). At exact boundaries like 3.145, floating-point representation (3.14499...) causes the boundary value to fall inside the tolerance. Options:
- Use test values clearly inside/outside boundaries (e.g., 3.146 instead of 3.145)
- Or adjust to `<=` comparison (but this changes semantics to closed interval [3.135, 3.145])
