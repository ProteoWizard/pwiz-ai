# TODO-20260710_calculated_report_column.md

## Branch Information
- **Branch**: `Skyline/work/20260710_calculated_report_column`
- **Base**: `master`
- **Created**: 2026-07-10
- **Status**: In Progress
- **GitHub Issue**: [#4417](https://github.com/ProteoWizard/pwiz/issues/4417)
- **PR**: (pending)

## Objective

Add a per-report calculated-value column to the Document Grid: a column whose value is a
small arithmetic formula (NCalc) over other numeric report fields. The definition lives in
the `ViewSpec` so it travels in `.skyr` / in-document views and is language-invariant.

## Key Decisions

- **Per-report storage** on `ColumnSpec` (`Formula` + `Operands`), not document-level, and
  not an extension of calculated annotations.
- **Serialization is attribute-only** (`calculated` / `formula` / `operandN`) so the
  `<column>` stays childless and older Skyline degrades gracefully (ignores unknown
  attributes; renders `#COLUMN NOT FOUND#`). No format-version bump.
- **Stored form is language-invariant**: canonical `[cN]` tokens + operand `PropertyPath`s;
  the display caption is resolved fresh from the schema each render.
- **Evaluator**: CoreCLR-NCalc 3.1.253 (MIT, net472 via netstandard2.0; single transitive
  dep Antlr4.Runtime.Standard). Parse once, per-eval `Expression` (thread-safe for the grid's
  worker threads), InvariantCulture, `EvaluateOptions.NoCache`.
- **Divide-by-zero / non-finite** shown as `Infinity`/`NaN` as-is (matches ratio columns,
  which have no zero guard). Null operand -> blank (never a silent zero). `#ERROR#` only on a
  thrown eval; `#NAME#` when an operand no longer resolves.
- **Collection operands re-root the report**: referencing a field under a deeper collection
  (e.g. a transition Product m/z on a Precursors report) makes the whole report re-root to
  that deeper row type (the grid "adds lines"), exactly as displaying the field directly does.
  Implemented by teaching `DocumentViewTransformer` to treat calc operands as column paths for
  both row-type detection (`AnyColumnsWithPrefix`) and cross-frame remapping (`MapColumnSpec`),
  and by rooting the calc dialog in the same (transformed) frame the normal Add Column tree uses.
- **Entry point**: an "fx" icon toolstrip button on the columns tab (below Remove/Up/Down,
  past a separator) + a right-click context-menu entry. The icon is drawn at runtime.
- **Numeric-only field picker**: rule is "if a field is a suitable numeric report column, it
  is usable as an operand" -- numeric fields stay reachable including through collections;
  non-numeric fields and dead-end branches are hidden.
- **Formula-as-tooltip**: the display formula (`[cN]` -> current operand captions) shows as
  the column's description/tooltip wherever its name appears (grid header + editor list).

## Files

New:
- `pwiz_tools/Shared/Common/DataBinding/CalculatedColumnEvaluator.cs`
- `pwiz_tools/Shared/Common/DataBinding/Controls/Editor/CalculatedColumnDlg.{cs,Designer.cs,resx}`
- `pwiz_tools/Skyline/CommonTest/DataBinding/CalculatedColumnEvaluatorTest.cs`
- `pwiz_tools/Skyline/TestFunctional/CalculatedColumnTest.cs`

Changed (Common):
- `DataBinding/ColumnSpec.cs` (Formula/Operands + attribute serialization + Equals/GetHashCode)
- `DataBinding/ColumnDescriptor.cs` (Calculated subclass; GetReferencedColumns;
  GetCalculatedColumnDescription; operand unwrap via DataSchema.UnwrapValue)
- `DataBinding/ViewInfo.cs` (MakeCalculatedColumnDescriptor; GetCollectionColumns operands)
- `DataBinding/DataSchema.cs` (GetColumnDescription returns calc formula)
- `DataBinding/Controls/BoundDataGridView.cs` (OnColumnAdded -> header tooltip)
- `DataBinding/Controls/Editor/AvailableFieldsTree.cs` (IsLeafFieldSelectable numeric filter)
- `DataBinding/Controls/Editor/ChooseColumnsTab.{cs,Designer.cs,resx}` (fx button + tooltips)
- `Common.csproj` (CoreCLR-NCalc PackageReference), `Properties/Resources.{resx,Designer.cs}`

Changed (Skyline):
- `Model/Databinding/DocumentViewTransformer.cs` (calc-operand re-root + remap)
- `Executables/Installer/FileList64-template.txt`, `Product-template.wxs` (NCalc + Antlr4 DLLs)
- test project registrations + `TestRunnerLib/TestRunnerFormLookup.csv`

## Status / Verification

- [x] Data model + serialization (attribute-only, round-trip test)
- [x] Evaluator + unit tests (arithmetic, null propagation, non-finite, every advertised function)
- [x] Editor dialog, validation gates, numeric-only picker, Help
- [x] fx toolbar button + context menu
- [x] Collection-operand re-rooting (functional test: transition Product m/z -> rows expand)
- [x] Formula-as-tooltip (grid header + editor list; functional assertion)
- [x] Installer + packaging
- [x] Self-review (fixed AnnotatedValue operand unwrap) + CodeInspection + full ReSharper: 0/0
- [ ] Strip demo `PauseTest` from the functional test before commit
- [ ] Commit code to feature branch (new third-party dependency -- confirm with developer)
- [ ] Open PR (Fixes #4417), `/pw-self-review`, TeamCity

## Notes

- New third-party dependency (CoreCLR-NCalc). Empirically chosen over the modern NCalcSync
  line, which drags ~28 transitive .NET 9 packages and a moderate advisory onto net472.
- The `plan` file from planning: `~/.claude/plans/let-s-think-about-a-wild-lantern.md`.
