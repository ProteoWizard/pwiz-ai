# TODO-20260828_designer_serialization_visibility.md

## Branch Information
- **Branch**: `Skyline/work/20260828_designer_serialization_visibility`
- **Module**: `skyline`
- **Base**: `master` (baac9d4a0)
- **Created**: 2026-08-28
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (pending)

## Objective

Fix every WFO1000 warning in master so the .NET port branch does not have to carry
them. WFO1000 ("Property does not configure the code serialization for its property
content") fires on public/internal settable properties of any `IComponent` that has
neither `[DefaultValue]`, nor `[DesignerSerializationVisibility]`, nor a
`ShouldSerialize<Name>()` method. Without one of those, the Windows Forms designer
serializes the property into `InitializeComponent` - which for transient runtime
state produces stale, misleading assignments in `.Designer.cs`.

Master targets .NET Framework 4.7.2 and cannot run the analyzer, so the warnings
were only visible from the port branch. See "Tooling" below for how they were made
visible here.

## Context

- The .NET 10 port branch reported 807 WFO1000 warnings.
- Master (net472) contains exactly the same 807 - verified set-equal, 0 differences.
- Only 38 of the 807 were being written by the designer at all. The other 769 are
  purely transient and had simply never been marked.
- Several of the 38 were exactly the pollution this warning exists to prevent, e.g.
  `SkylineTesterWindow.Designer.cs` was serializing `commandShell.RunStartTime`,
  `StopButton`, `FilterFunc`, `IsWaiting`, `NextCommand`.

## Tooling

Built under `ai/.tmp/sessions/20260828-f7d6f7f0/` (not committed):

- **`wfoscan`** - runs the real `System.Windows.Forms.Analyzers.CSharp.dll` (from the
  .NET 10 WindowsDesktop ref pack) over a Roslyn compilation built from each
  old-style `.csproj`'s `Compile` items, against the .NET Framework 4.7.2 reference
  assemblies plus `pwiz_tools/Skyline/bin/x64/Release` for third-party references.
  This is what makes WFO1000 visible on a net472 checkout.
- **`wfofix`** - syntax-guided textual rewriter that inserts a given attribute above
  a property (correct indentation, after doc comments, above existing attribute
  lists) and adds `using System.ComponentModel;` where needed. Textual rather than
  Roslyn-formatted so file encoding and line endings are preserved exactly.
- **`wfoorphan`** - finds designer assignments that were orphaned by this change.
  Builds the same compilations, then walks every `*.Designer.cs` and resolves each
  assignment's left side through the semantic model, reporting any whose target
  property carries `DesignerSerializationVisibility` or `DefaultValue`. Resolving
  symbols rather than matching text is what catches inherited-form root writes and
  properties declared in a sibling repo assembly. Two gotchas it cost to learn:
  `DesignerSerializationVisibility` is `Hidden=0, Visible=1, Content=2` (not the
  order the names suggest), and the `--libdir` must point at a build *newer* than
  the edits or cross-assembly attributes silently read as absent.

Validation of the harness:
1. A 19-case synthetic probe built with `dotnet build` emits 16 WFO1000; `wfoscan`
   reproduces exactly those 16, and gives identical results against net10 and
   net472 reference assemblies.
2. `wfoscan` on master finds 807; the port branch's build log has the same 807.
   Set comparison on file+property: 0 differences either way.

## Implementation Plan

### Phase 1: transient properties (769) ✅

- [x] Add `[DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]`
      to all 769 properties no designer writes
- [x] Add `using System.ComponentModel;` to the 143 files that lacked it

### Phase 2: the 38 the designer writes ✅

Classified individually against the actual `.Designer.cs` assignment:

- [x] **23 hidden** - runtime state the designer had captured:
      `CommandShell` (13), `AsyncChromatogramsGraph2` (3),
      `IonMobilityFilteringUserControl` (3), `AvailableFieldsTree.CheckedColumns`,
      `BindingListSource.NewRowHandler`, `SequenceTree.LockDefaultExpansion`,
      `WindowThumbnail.ProcessId`
- [x] **14 given `[DefaultValue]`** - genuine design-time settings, default verified
      against the actual field initializer / child-control default:
      `ChooseViewsControl` (6), `DendrogramControl` (2), `NavBar` (2),
      `CustomTextProgressBar` (2), `MsGraphExtension` (1),
      `ZedGraphControl.ScrollGrace` (1)
- [x] **1 given `[DesignerSerializationVisibility(Visible)]`** -
      `AlphaColorPickerButton.SelectedColor`, whose default
      (`Color.FromArgb(0, Color.Empty)`) is not expressible as a constant

### Phase 3: stale designer assignments ✅

- [x] Removed 25 assignments that are provable no-ops (auto-property or guarded
      setter being handed its own default). Each setter was read to confirm.
- [x] **Second sweep, semantic** - the first sweep was textual and matched only
      `this.<field>.<Prop> =` with the field's *declared* type, so it missed
      root-level `this.<Prop> =` writes on visually-inherited forms and every
      cross-assembly property (e.g. `BoundDataGridView` lives in `pwiz.Common`,
      which Skyline consumes as a DLL). Built `wfoorphan` (below) to resolve
      assignment targets through the Roslyn semantic model instead. It found
      **18** more orphaned writes; all 18 verified as no-ops and removed:
      - `TreeViewMS` x6 (`SequenceTreeForm`, `FilesTreeForm`) - ctor sets
        `AutoExpandSingleNodes = true` and `UseKeysOverride = false`;
        `RestoredFromPersistentString` is a plain `bool` auto-property
      - `ColorGrid` x4 (`EditCustomThemeDlg`, `VolcanoPlotFormattingDlg`) -
        forwards to an inner `DataGridView` that the control's own designer
        never touches, so `AllowUserToAddRows = true` /
        `AllowUserToOrderColumns = false` are the framework defaults
      - `IonMobilityFilteringUserControl` x6 - see reversal note below
      - `BoundDataGridView.ReportColorScheme = null` - reference-type auto-property
      - `DocumentGridForm.ShowViewsMenu = true` (`AuditLogForm`) - the one
        root-level write on an inherited form; default is already `true`

### Phase 4: verification ✅

- [x] `wfoscan` re-run: **0** WFO1000 remaining across all 25 projects
- [x] `wfoorphan` re-run: **0** designer writes to `Hidden` properties remain
- [x] No mixed line endings introduced (202 changed files checked)
- [x] `Build-Skyline.ps1` - solution builds clean (Debug)
- [x] `CodeInspectionTest` - passed
- [x] Functional tests for every form whose designer file changed - 7 tests,
      0 failures: `TestIonMobility`, `TestAuditLog`, `TestEditCustomTheme`,
      `TestVolcanoPlotFormatting`, `TestFilesTreeForm`,
      `TestSequenceTreeExpansion`, `TestDocumentGrid`

## Reversed on review

- **`IonMobilityFilteringUserControl` (6 designer lines) - now deleted.** These
  were originally kept on the theory that `WindowWidthType`'s setter has real
  side effects (`comboBoxWindowType.SelectedIndex = (int)value` plus
  `UpdateIonMobilityFilterWindowWidthControls()`) and so the host designer lines
  were load-bearing at construction. Reading the control end to end shows they
  are not. The control's own ctor already calls
  `UpdateIonMobilityFilterWindowWidthControls()`, and that method opens with
  `if (comboBoxWindowType.SelectedIndex < 0) SelectedIndex = (int)none;`. The
  control's designer never assigns `SelectedIndex`, so it starts at `-1` and the
  ctor sets it to `none` - exactly what the host designer line then re-assigned.
  Likewise `cbUseSpectralLibraryIonMobilities.Checked` and
  `textIonMobilityFilterResolvingPower.Text` are never set in the control's
  designer, so `= false` / `= null` are the framework defaults. All six are
  no-ops. `TestIonMobility` passes with them gone.

  The original note also contradicted itself: it justified keeping designer
  output while marking the very properties `Hidden`, which is the instruction
  that stops the designer regenerating that output.

## Deliberately NOT done

- **Designer lines for the 14 `[DefaultValue]` properties.** Left in place. Those
  properties are legitimately designer-managed; the designer will drop the ones
  that now equal the declared default on its next regeneration.

## Open - not yet fixed

- **`ImageListBoxItem.Text` must not be `Hidden` (`Controls/ImageListBox.cs`).**
  This is the one property in the change that the designer serializes into
  **`.resx`** rather than into `InitializeComponent`, and the Phase 3 sweeps only
  ever looked at `.Designer.cs`. `ImageListBox.Items` carries
  `[DesignerSerializationVisibility(Content)]` + `[Localizable(true)]`, so the
  designer walks each item and routes `Text` into resources;
  `NoModeUIDlg.Designer.cs` calls `resources.ApplyResources` on all three items and
  the captions live at `NoModeUIDlg.resx:175/181/187` with matching entries in
  `.ja.resx` and `.zh-CHS.resx`. `Hidden` suppresses the resource serializer too,
  so the next designer save of that form drops all nine entries and the UI-mode
  chooser renders three blank rows in every language. Fix is `[DefaultValue("")]`
  (the parameterless ctor is `ImageListBoxItem() : this("")`), matching the
  treatment already given to the sibling `ImageIndex` (`[DefaultValue(-1)]`).

## Follow-up worth considering

Master has no way to keep this fixed - the analyzer cannot run on net472. A
`CodeInspectionTest`-style guard, or folding `wfoscan` into the test suite, would
stop the 807 from creeping back before the port lands.
