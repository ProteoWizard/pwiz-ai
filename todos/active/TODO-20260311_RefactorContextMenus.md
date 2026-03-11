# TODO-20260311_RefactorContextMenus.md

## Branch Information
- **Branch**: `Skyline/work/20260311_RefactorContextMenus`
- **Base**: `master`
- **Created**: 2026-03-11
- **Status**: In Progress
- **GitHub Issue**: [#4073](https://github.com/ProteoWizard/pwiz/issues/4073)
- **PR**: (pending)

## Objective

Refactor ContextMenuStrip instances out of Skyline.Designer.cs into separate SkylineControl classes, following the ChromatogramContextMenu pattern. For graph menus, create fresh instances each time a context menu is needed (using `using` statement), eliminating the "DropDownItems.Count == 0" lazy initialization pattern. The contextMenuTreeNode can be created once since it's not used with ZedGraphControl.

## Prior Work

- Commit e01c555ad: Established the pattern by extracting ChromatogramContextMenu into its own SkylineControl class

## Context Menus to Refactor

| ContextMenuStrip | New Class | Usage Pattern |
|---|---|---|
| contextMenuSpectrum | SpectrumContextMenu | Create per-use, dispose after |
| contextMenuRetentionTimes | RetentionTimesContextMenu | Create per-use, dispose after |
| contextMenuPeakAreas | PeakAreasContextMenu | Create per-use, dispose after |
| contextMenuMassErrors | MassErrorsContextMenu | Create per-use, dispose after |
| contextMenuDetections | DetectionsContextMenu | Create per-use, dispose after |
| contextMenuTreeNode | TreeNodeContextMenu | Create once (not ZedGraph) |

## Key Files

- `pwiz_tools/Skyline/Skyline.Designer.cs` - Remove context menu fields
- `pwiz_tools/Skyline/Skyline.resx` - Move resources to new .resx files
- `pwiz_tools/Skyline/SkylineGraphs.cs` - Move BuildXxxMenu methods to new classes
- `pwiz_tools/Skyline/Menus/ChromatogramContextMenu.cs` - Reference pattern
- `pwiz_tools/Skyline/Menus/ChromatogramContextMenu.Designer.cs` - Reference pattern
- `pwiz_tools/Skyline/Menus/SkylineControl.cs` - Base class

## Tasks

### Phase 1: Graph Context Menus (create per-use)
- [ ] Create SpectrumContextMenu (SkylineControl)
  - Move from: `GraphSpectrum.IStateProvider.BuildSpectrumMenu` in SkylineGraphs.cs
  - Move fields: contextMenuSpectrum and all its menu items from Skyline.Designer.cs
  - Move handlers: spectrum menu event handlers from SkylineGraphs.cs
- [ ] Create RetentionTimesContextMenu (SkylineControl)
  - Move from: `BuildRTGraphMenu` in SkylineGraphs.cs
  - Move fields: contextMenuRetentionTimes and all its menu items
  - Move handlers: RT menu event handlers
  - Remove: "DropDownItems.Count == 0" checks (lines ~2903, 2913, 2927, 2939, 2960, 3001, 3036)
- [ ] Create PeakAreasContextMenu (SkylineControl)
  - Move from: `BuildAreaGraphMenu` in SkylineGraphs.cs
  - Move fields: contextMenuPeakAreas and all its menu items
  - Move handlers: area menu event handlers
  - Remove: "DropDownItems.Count == 0" checks (lines ~3800, 3815, 3922, 3936, 3949, 3968)
- [ ] Create MassErrorsContextMenu (SkylineControl)
  - Move from: `BuildMassErrorGraphMenu` in SkylineGraphs.cs
  - Move fields: contextMenuMassErrors and all its menu items
  - Move handlers: mass error menu event handlers
  - Remove: "DropDownItems.Count == 0" checks (lines ~5029, 5119, 5133, 5148, 5163)
- [ ] Create DetectionsContextMenu (SkylineControl)
  - Move from: `BuildDetectionsGraphMenu` in SkylineGraphs.cs
  - Move fields: contextMenuDetections and all its menu items
  - Move handlers: detection menu event handlers

### Phase 2: Tree Node Context Menu (create once)
- [ ] Create TreeNodeContextMenu (SkylineControl)
  - Move fields: contextMenuTreeNode and all its menu items from Skyline.Designer.cs
  - Move handlers: tree node context menu event handlers
  - This one is created once, not per-use

### Phase 3: Cleanup & Verification
- [ ] Update Skyline.csproj with new files
- [ ] Build successfully
- [ ] Run CodeInspection test
- [ ] Run functional tests related to context menus
- [ ] Verify no "DropDownItems.Count == 0" patterns remain for migrated menus

## Pattern Reference

```csharp
// In SkylineGraphs.cs - how each Build method should look after refactor:
void GraphSummary.IStateProvider.BuildGraphMenu(ZedGraphControl zedGraphControl,
    ContextMenuStrip menuStrip, Point mousePt, GraphSummary.IController controller)
{
    // ... controller type check ...
    using var rtContextMenu = new RetentionTimesContextMenu(this);
    rtContextMenu.BuildRTGraphMenu(graph, menuStrip, mousePt, controller);
}
```

## Notes

- The "DropDownItems.Count == 0" pattern exists because menu items would disappear when a ZedGraphControl was disposed (it would dispose its ContextMenuStrip which would take ownership of inserted items). By creating fresh menus each time, we don't need this defensive check.
- contextMenuTreeNode does NOT need the create-per-use pattern since it's assigned directly to the tree control, not inserted into ZedGraph menus.
