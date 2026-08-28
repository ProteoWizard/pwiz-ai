# TODO-20260828_designer_serialization_visibility.md

## Branch Information
- **Branch**: `Skyline/work/20260828_designer_serialization_visibility`
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

### Phase 4: verification

- [x] `wfoscan` re-run: **0** WFO1000 remaining across all 25 projects
- [x] No mixed line endings introduced (202 changed files checked)
- [x] `Build-Skyline.ps1` - solution builds clean
- [ ] `CodeInspectionTest`
- [ ] Spot functional tests for the forms whose designer files changed

## Deliberately NOT done

- **`IonMobilityFilteringUserControl` (6 designer lines kept).** The three properties
  are hidden, but `WindowWidthType`'s setter has real side effects - it sets
  `comboBoxWindowType.SelectedIndex` and calls
  `UpdateIonMobilityFilterWindowWidthControls()`. Those lines in
  `FullScanSettingsControl.Designer.cs` and `TransitionSettingsUI.Designer.cs` are
  load-bearing at construction time, not stale. They will disappear the next time
  either form is opened in the designer, so the control should be made to
  initialize itself (call `UpdateIonMobilityFilterWindowWidthControls()` from its
  own constructor) before that happens. Worth a follow-up item.

- **Designer lines for the 14 `[DefaultValue]` properties.** Left in place. Those
  properties are legitimately designer-managed; the designer will drop the ones
  that now equal the declared default on its next regeneration.

## Follow-up worth considering

Master has no way to keep this fixed - the analyzer cannot run on net472. A
`CodeInspectionTest`-style guard, or folding `wfoscan` into the test suite, would
stop the 807 from creeping back before the port lands.
