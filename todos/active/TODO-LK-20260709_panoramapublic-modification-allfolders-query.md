# TODO-LK: panoramapublic modification web parts exposed an unbounded "All Folders" aggregate query

- **Status**: PR OPEN, awaiting review/merge.
- **PR**: #662 (https://github.com/LabKey/MacCossLabModules/pull/662)
- **Branch**: `26.3_fb_panoramapublic-disable-cross-folder-query`, off `release26.3-SNAPSHOT`
- **Module**: panoramapublic (`server/modules/MacCossLabModules/panoramapublic`)
- **Origin**: PanoramaWeb scraping incident, 2026-07-08/09. The longest request was a
  `query-executeQuery.view` on the modification query, running 1,006 s at HTTP 200.

## Problem

The "Isotope Modifications" and "Structural Modifications" web parts show a small folder-scoped grid, but
the web part title links to the full query grid (`IsotopeModifications` / `StructuralModifications` on
`query-executeQuery.view`). There the Folder Filter offered "All Folders", running the aggregate across
every targetedms folder on the server. Trimming the dropdown alone does not fix it: the applied filter comes
straight from `?query.containerFilterName=` in the URL, so a hand-built `AllFolders` URL bypasses the
dropdown. This affects both the executeQuery grid and the standalone web part grid.

## Fix (PR #662)

- `PanoramaPublicSchema.limitContainerScope(cf, container, user)` returns `CurrentAndSubfolders` for any
  filter type other than `Current` or `CurrentAndSubfolders`, else returns `cf` unchanged.
- Applied via a `getContainerFilter()` override in both `PanoramaPublicSchema.createView` (executeQuery grid)
  and `ModificationsView` (standalone web parts). Both also trim the dropdown with
  `setAllowableContainerFilterTypes(Current, CurrentAndSubfolders)`.
- Constants `QUERY_ISOTOPE_MODIFICATIONS` / `QUERY_STRUCTURAL_MODIFICATIONS`.
- Tests in `PanoramaPublicModificationsTest.testAddModInfo`: `verifyModificationQueryScopeIsRestricted` and
  `verifyModificationWebPartScopeIsRestricted`. Red on unfixed code, green after.

## Open items

- **PR #662** review and merge. Optional Copilot pass, then `/pw-respond 662`.

